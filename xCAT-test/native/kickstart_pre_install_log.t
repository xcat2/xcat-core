#!/usr/bin/env perl
use strict;
use warnings;

use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::Test::Sandbox qw(sandbox_root sandbox_run);
use XCAT::Test::Template qw(template_database set_row render_template);

plan skip_all => 'kickstart execution requires Linux' unless $^O eq 'linux';
my $database = template_database();

# The kickstart templates whose %pre writes /tmp/pre-install.log, each with an OS that uses it.
my @templates = (
    [ 'rh/compute.rhels10.tmpl',            'rhels10.0',         'x86_64',  'rh' ],
    [ 'rh/compute.rhels9.tmpl',             'alma9.6',           'x86_64',  'rh' ],
    [ 'rh/compute.rhels8.tmpl',             'rocky8.10',         'x86_64',  'rh' ],
    [ 'centos/compute.centos8.tmpl',        'centos8',           'x86_64',  'centos' ],
    [ 'openeuler/compute.openeuler.tmpl',   'openeuler24.03sp3', 'x86_64',  'openeuler' ],
    [ 'rh/compute.rhels10.riscv64.tmpl',    'rhels10.0',         'riscv64', 'rh' ],
    [ 'rocky/service.rocky10.riscv64.tmpl', 'rocky10.2',         'riscv64', 'rocky' ],
);
my $diagnostic = "pre-install fixture diagnostic\n";

for my $case (@templates) {
    my ($template, $os, $arch, $platform) = @$case;
    subtest $template => sub {
        set_row('nodetype', {node => 'node'}, {os => $os, arch => $arch, provmethod => 'install'});
        my $path = repo_path("xCAT-server/share/xcat/install/$template");
        (my $pkglist = $path) =~ s/\.tmpl$/.pkglist/;
        $pkglist = '' unless -r $pkglist;
        my $output = "$database/ks";
        render_template($database, $path, $output, 'node', $pkglist, '/install/media', $platform, undef,
            {xcatmaster => '192.0.2.1'});
        my $ks = read_text($output);
        like($ks, qr/^%pre\b.*?pre-install\.log.*?^%end/ms, 'the %pre block writes the pre-install log');

        my @posts;
        while ($ks =~ /^%post([^\n]*)\n(.*?)^%end/msg) {
            push @posts, [$1, $2];
        }
        my @installer = grep { $posts[$_][0] =~ /(?:^|\s)--nochroot(?:\s|$)/ } 0 .. $#posts;
        my ($chroot) = grep { $posts[$_][0] !~ /(?:^|\s)--nochroot(?:\s|$)/ } 0 .. $#posts;
        ok(defined $chroot, 'has a %post block that runs in the installed system');

        # anaconda keeps the installer's /tmp out of the chroot, so only a --nochroot block can read the log
        my $root = sandbox_root();
        make_path("$root/installer-tmp");
        write_text("$root/installer-tmp/pre-install.log", $diagnostic);
        for my $index (@installer) {
            my ($interpreter) = $posts[$index][0] =~ /--interpreter=(\S+)/;
            write_text("$root/post.sh", $posts[$index][1]);
            my ($rc, $log) = sandbox_run($root, {
                writable => {"$root/installer-tmp" => '/tmp', "$root/log" => '/mnt/sysimage/var/log'},
            }, $interpreter // '/bin/sh', '/fixture/post.sh');
            is($rc, 0, "%post --nochroot block $index completes") or diag($log);
        }
        my $xcatlog = "$root/log/xcat/xcat.log";
        is(-f $xcatlog ? read_text($xcatlog) : '', $diagnostic,
            'copies the pre-install log into the installed system log');
        ok(@installer && defined $chroot && $installer[0] < $chroot,
            'copies it before the first %post block in the installed system writes that log');
    };
}

done_testing();
