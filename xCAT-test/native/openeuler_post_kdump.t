#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use Test::More;

use imgutils;
use XCAT::Test::File qw(repo_path);
use XCAT::Test::Process qw(run_command);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'kickstart %post execution requires Linux' unless $^O eq 'linux';
my $database = template_database();
require xCAT::SvrUtils;
set_row('passwd', {key => 'system', username => 'root'}, {password => '$6$fixture$encrypted'});
set_row('nodetype', {node => 'node'}, {os => 'openeuler24.03sp4', arch => 'riscv64', provmethod => 'install'});

my $dropin = 'etc/systemd/system/kdump.service.d/xcat-dump-memory.conf';
my $image = tempdir(CLEANUP => 1);
make_path("$image/usr/lib/systemd/system");
write_text("$image/usr/lib/systemd/system/kdump.service", "[Service]\n");
imgutils::skip_kdump_without_dump_memory($image);
my $stateless = read_text("$image/$dropin");

sub post_root {
    my (%units) = @_;
    my $root = sandbox_root();
    make_path("$root/units", "$root/etc/systemd/system", "$root/etc/yum.repos.d");
    write_text("$root/units/$_", $units{$_}) for keys %units;
    write_text("$root/tmp/pre-install.log", "pre-install fixture diagnostic\n");
    copy(repo_path('xCAT/postscripts/xcatlib.sh'), "$root/xcatlib.sh") or die $!;
    write_text("$root/mypostscript.node", "#!/bin/bash\nMASTER=192.0.2.1\ntouch /fixture/postscript-ran\n");
    for my $name (qw(curl logger sleep updateflag.awk nmcli openssl)) {
        copy(repo_path('xCAT-test/fixtures/install-profile/command'), "$root/bin/$name") or die $!;
        chmod 0755, "$root/bin/$name" or die $!;
    }
    return $root;
}

my $base = repo_path('xCAT-server/share/xcat/install/openeuler');
for my $profile (qw(compute service)) {
    subtest "$profile post-install sequence" => sub {
        my $tmpl = xCAT::SvrUtils->get_tmpl_file_name($base, $profile, 'openeuler24.03sp4', 'riscv64');
        my $pkglist = xCAT::SvrUtils->get_pkglist_file_name($base, $profile, 'openeuler24.03sp4', 'riscv64');
        my $output = "$database/$profile.ks";
        render_template($database, $tmpl, $output, 'node', $pkglist, '/install/media', 'openeuler', undef,
            {xcatmaster => '192.0.2.1'});
        my @posts;
        my $rendered = read_text($output);
        while ($rendered =~ /^%post([^\n]*)\n(.*?)^%end/msg) {
            push @posts, [$1, $2];
        }
        ok(@posts, 'renders a %post section');

        for my $case (
            [{'kdump.service' => "[Service]\nExecStart=/usr/bin/kdumpctl start\n"}, $stateless,
                'installs the drop-in that stateless images get'],
            [{'NetworkManager.service' => "[Service]\n"}, undef, 'adds no drop-in without kdump.service'],
        ) {
            my ($units, $expected, $label) = @$case;
            my $root = post_root(%$units);
            make_path("$root/etc/systemd/system/kdump.service.d");
            write_text("$root/etc/systemd/system/kdump.service.d/site.conf", "[Service]\nTimeoutSec=600\n");
            if (defined $expected) {
                write_text("$root/$dropin", "old policy\n");
                chmod oct('0640'), "$root/$dropin" or die $!;
            }
            my $index = 0;
            for my $post (@posts, @posts) {
                my ($interpreter) = $post->[0] =~ /--interpreter=(\S+)/;
                write_text("$root/post.sh", $post->[1]);
                my ($rc, $log) = sandbox_run($root, {read_only => {"$root/units" => '/usr/lib/systemd/system'}},
                    'timeout', '30', $interpreter // '/bin/sh', '/fixture/post.sh');
                is($rc, 0, '%post section ' . ++$index . ' completes')
                    or diag($log, read_text("$root/log/xcat/xcat.log"));
            }
            ok(-e "$root/postscript-ran", 'runs the rendered sequence through the downloaded postscript');
            ok(!-e "$root/unexpected-command", 'external fixtures accept the requested operations');
            is(-f "$root/$dropin" ? read_text("$root/$dropin") : undef, $expected, $label);
            is(read_text("$root/etc/systemd/system/kdump.service.d/site.conf"),
                "[Service]\nTimeoutSec=600\n", 'retains the administrator drop-in');
            is((stat("$root/$dropin"))[2] & oct('0777'), oct('0640'),
                'retains existing drop-in permissions') if defined $expected;
        }
    };
}

my $delivered = "$database/delivered";
my ($copy_rc, $copy_output) = run_command('cp', '-a', repo_path('xCAT-server'), $delivered);
die "copy delivered templates: $copy_output" if $copy_rc;
my $asset = "$delivered/share/xcat/netboot/imgutils/xcat-dump-memory.conf";
my $asset_bytes = read_text($asset);
for my $case (qw(missing unreadable trailing_newlines)) {
    subtest "delivered kdump policy: $case" => sub {
        local $ENV{XCATROOT} = $delivered;
        if ($case eq 'missing') {
            unlink($asset) or die $!;
        } elsif ($case eq 'unreadable') {
            chmod oct('0000'), $asset or die $!;
        } else {
            write_text($asset, $asset_bytes . "\n\n");
        }
        render_template($database, repo_path('xCAT-server/share/xcat/install/openeuler/compute.openeuler.tmpl'),
            "$database/policy.ks", 'node', '', '/install/media', 'openeuler', undef, {xcatmaster => '192.0.2.1'});
        my $root = post_root('kdump.service' => "[Service]\n");
        make_path("$root/etc/systemd/system/kdump.service.d");
        write_text("$root/$dropin", "previous policy\n");
        chmod oct('0640'), "$root/$dropin" or die $!;
        my $rendered = read_text("$database/policy.ks");
        my $chroot_posts = 0;
        while ($rendered =~ /^%post([^\n]*)\n(.*?)^%end/msg) {
            my ($options, $body) = ($1, $2);
            my ($interpreter) = $options =~ /--interpreter=(\S+)/;
            write_text("$root/post.sh", $body);
            my ($rc, $output) = sandbox_run($root, {read_only => {"$root/units" => '/usr/lib/systemd/system'}},
                'timeout', '30', $interpreter // '/bin/sh', '/fixture/post.sh');
            if ($options =~ /--nochroot/ || $case eq 'trailing_newlines') {
                is($rc, 0, 'the valid installer stage completes') or diag($output);
            } else {
                ++$chroot_posts;
                like($options, qr/--erroronfail/, 'anaconda treats the failed stage as fatal');
                isnt($rc, 0, 'the unavailable policy fails the chroot stage');
                like($output . read_text("$root/log/xcat/xcat.log"), qr/INCLUDEBAD:cannot open .*xcat-dump-memory\.conf/,
                    'reports the missing policy include');
            }
        }
        ok($chroot_posts, 'exercised a failing chroot stage') unless $case eq 'trailing_newlines';
        is(read_text("$root/$dropin"), $case eq 'trailing_newlines' ? $asset_bytes . "\n\n" : "previous policy\n",
            'valid policy bytes are exact; an unavailable policy leaves the old drop-in intact');
        is((stat("$root/$dropin"))[2] & oct('0777'), oct('0640'), 'retains the drop-in permissions');
        chmod oct('0644'), $asset or die $! if -e $asset;
        write_text($asset, $asset_bytes);
    };
}

done_testing();
