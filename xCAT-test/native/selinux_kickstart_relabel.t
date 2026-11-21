#!/usr/bin/env perl
use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'kickstart %post execution requires Linux' unless $^O eq 'linux';
my $database = template_database();
set_row('passwd', {key => 'system', username => 'root'}, {password => '$6$fixture$encrypted'});

my $install = repo_path('xCAT-server/share/xcat/install');
my @templates = (
    ['rh/compute.rhels8.tmpl',            'rocky8.10',         'x86_64',  'rh'],
    ['rh/compute.rhels9.tmpl',            'alma9.6',           'x86_64',  'rh'],
    ['rh/compute.rhels10.tmpl',           'rhels10.0',         'x86_64',  'rh'],
    ['rh/compute.rhels10.riscv64.tmpl',   'rhels10.0',         'riscv64', 'rh'],
    ['rocky/service.rocky10.riscv64.tmpl', 'rocky10.2',        'riscv64', 'rocky'],
    ['openeuler/compute.openeuler.tmpl',  'openeuler24.03sp3', 'x86_64',  'openeuler'],
);

# The stand-in records what the xCAT post scripts had done when the relabel ran.
my $restorecon = <<'SH';
#!/bin/sh
{
    printf 'args=%s\n' "$*"
    [ -e /fixture/postscript-ran ] && echo 'postscript=ran'
    grep -q '^enabled=0$' /etc/yum.repos.d/rocky.repo && echo 'vendor-repository=disabled'
} >>/fixture/restorecon.calls
SH

sub post_root {
    my $root = sandbox_root();
    make_path("$root/sbin", "$root/etc/systemd/system", "$root/etc/yum.repos.d", "$root/boot/efi/EFI/BOOT");
    write_text("$root/sbin/restorecon", $restorecon);
    chmod 0755, "$root/sbin/restorecon" or die $!;
    write_text("$root/etc/yum.repos.d/rocky.repo", "[baseos]\nname=BaseOS\nenabled=1\n");
    write_text("$root/boot/efi/EFI/BOOT/BOOTRISCV64.EFI", "loader\n");
    write_text("$root/tmp/pre-install.log", "pre-install fixture diagnostic\n");
    copy(repo_path('xCAT/postscripts/xcatlib.sh'), "$root/xcatlib.sh") or die $!;
    write_text("$root/mypostscript.node", "#!/bin/bash\nMASTER=192.0.2.1\ntouch /fixture/postscript-ran\n");
    for my $name (qw(curl logger sleep updateflag.awk nmcli openssl)) {
        copy(repo_path('xCAT-test/fixtures/install-profile/command'), "$root/bin/$name") or die $!;
        chmod 0755, "$root/bin/$name" or die $!;
    }
    return $root;
}

for my $case (@templates) {
    my ($template, $os, $arch, $platform) = @$case;
    for my $mode (qw(enforcing disabled)) {
        subtest "$template $mode" => sub {
            set_row('nodetype', {node => 'node'}, {os => $os, arch => $arch, provmethod => 'install'});
            set_row('noderes', {node => 'node'}, {selinux => $mode});
            (my $pkglist = "$install/$template") =~ s/\.tmpl$/.pkglist/;
            my $output = "$database/ks";
            render_template($database, "$install/$template", $output, 'node', (-r $pkglist ? $pkglist : ''),
                '/install/media', $platform, undef, {xcatmaster => '192.0.2.1'});
            my $rendered = read_text($output);
            my @posts;
            while ($rendered =~ /^%post([^\n]*)\n(.*?)^%end/msg) {
                push @posts, [$1, $2];
            }
            ok(@posts, 'renders a %post section');

            my $root = post_root();
            my $index = 0;
            for my $post (@posts) {
                my ($interpreter) = $post->[0] =~ /--interpreter=(\S+)/;
                write_text("$root/post.sh", $post->[1]);
                my ($rc, $log) = sandbox_run($root, {read_only => {"$root/sbin" => '/usr/sbin'}},
                    'timeout', '30', $interpreter // '/bin/sh', '/fixture/post.sh');
                is($rc, 0, '%post section ' . ++$index . ' completes')
                    or diag($log, read_text("$root/log/xcat/xcat.log"));
            }
            ok(-e "$root/postscript-ran", 'runs the rendered sequence through the downloaded postscript');
            ok(!-e "$root/unexpected-command", 'external fixtures accept the requested operations');
            is(read_text("$root/etc/yum.repos.d/rocky.repo"), "[baseos]\nname=BaseOS\nenabled=0\n",
                'disables the installed vendor repository');
            my $calls = -e "$root/restorecon.calls" ? read_text("$root/restorecon.calls") : undef;
            if ($mode eq 'disabled') {
                is($calls, undef, 'does not relabel a disabled node');
            } else {
                is($calls, "args=-RF /xcatpost /opt/xcat /etc /root /var/log\npostscript=ran\nvendor-repository=disabled\n",
                    'relabels once, after the xCAT post scripts wrote their files');
            }
        };
    }
}

done_testing();
