#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Slurper qw(read_text write_text);
use File::Temp qw(tempdir);
use FindBin;
use Test::More;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use XCAT::Test::File qw(repo_path);

my $root = tempdir(CLEANUP => 1);
local $ENV{XCATROOT} = repo_path('xCAT-server');
local $ENV{XCATCFG} = "$root/config";
make_path($ENV{XCATCFG});
local %::XCATSITEVALS = (tftpdir => "$root/tftpboot", xcatdebugmode => 0);
require xCAT::Table;
require xCAT::NetworkUtils;

no warnings 'redefine';
local *xCAT::Table::new = sub { die 'Unexpected database access'; };
local *xCAT::NetworkUtils::getipaddr = sub {
    my ($class, $host) = @_;
    return '192.0.2.1' if $host eq 'server';
    return '192.0.2.2' if $host eq 'node';
    die "Unexpected hostname: $host";
};
use warnings 'redefine';

require(repo_path('xCAT-server/lib/xcat/plugins/grub2.pm'));

my @cases = (
    ['HTTP custom port', 'grub2-http', 8080, 'http,192.0.2.1:8080', 1],
    ['HTTP default port', 'grub2-http', undef, 'http,192.0.2.1', 1],
    ['HTTP explicit port 80', 'grub2-http', 80, 'http,192.0.2.1', 1],
    ['TFTP ignores HTTP port', 'grub2-tftp', 8080, 'tftp,192.0.2.1', 0],
    ['plain grub2 uses TFTP', 'grub2', 8080, 'tftp,192.0.2.1', 0],
    ['missing netboot uses TFTP', undef, 8080, 'tftp,192.0.2.1', 0],
    ['blank netboot uses TFTP', '', 8080, 'tftp,192.0.2.1', 0],
);
push @cases, map { ["reject $_", $_, 8080] }
    qw(grub2-https grub2-httpx grub2-xtftp grub2-ftp grub2- grub2-HTTP grub2-TFTP);

for my $arch (qw(x86_64 ppc64le aarch64 riscv64)) {
    for my $case (@cases) {
        my ($name, $netboot, $port, $expected_root, $http_paths) = @$case;
        subtest "$arch: $name" => sub {
            my $tftpdir = tempdir(DIR => $root, CLEANUP => 1);
            my $bootdir = "$tftpdir/boot/grub2";
            make_path($bootdir);
            my $loader_arch = $arch eq 'ppc64le' ? 'ppc' : $arch;
            write_text("$bootdir/grub2.$loader_arch", "fixture loader\n");
            local $::XCATSITEVALS{httpport} = $port;
            delete $::XCATSITEVALS{httpport} unless defined $port;
            my %noderes = (tftpserver => 'server');
            $noderes{netboot} = $netboot if defined $netboot;
            my $cwd = getcwd();
            my @result = xCAT_plugin::grub2::setstate(
                'node',
                {node => [{kernel => 'images/vmlinuz', initrd => 'images/initrd.img', kcmdline => 'quiet'}]},
                {node => [{currstate => 'install'}]},
                {node => [{mac => '02:00:00:00:00:02'}]},
                $tftpdir, {node => [\%noderes]}, {}, $arch, 'linux',
            );
            chdir($cwd) or die "Cannot restore working directory: $!";

            my $config = -f "$bootdir/node" ? read_text("$bootdir/node") : '';
            if (!defined $expected_root) {
                is_deeply(\@result,
                    [1, 'Invalid netboot method, please check noderes.netboot for node'],
                    'invalid protocol is reported');
                unlike($config, qr/^\s*(?:menuentry|set root=|linux\S*\s|initrd\S*\s)/m,
                    'invalid protocol creates no deployment entry');
                ok(!-e "$bootdir/grub2-node", 'invalid protocol publishes no loader');
                ok(!-e "$bootdir/grub.cfg-C0000202", 'invalid protocol publishes no IP alias');
                ok(!-e "$bootdir/grub.cfg-01-02-00-00-00-00-02", 'invalid protocol publishes no MAC alias');
                return;
            }

            is_deeply(\@result, [0, ''], 'configuration succeeds');
            my @entries = $config =~ /^menuentry "xCAT OS Deployment" \{\n([^}]+)^\}/mg;
            is(scalar @entries, 1, 'one deployment menu entry is rendered');
            my $entry = $entries[0] // '';
            my @roots = $entry =~ /^\s*set root=(.*)$/mg;
            is_deeply(\@roots, [$expected_root], 'transfer protocol and port are correct');
            my $prefix = $http_paths ? $tftpdir : '';
            my $efi = $arch eq 'x86_64' ? 'efi' : '';
            my @kernels = $entry =~ /^\s*(linux\S* .*)$/mg;
            is_deeply(\@kernels,
                ["linux$efi $prefix/images/vmlinuz quiet BOOTIF=\$net_default_mac"],
                'kernel path and arguments are rendered');
            my @initrds = $entry =~ /^\s*(initrd\S* .*)$/mg;
            is_deeply(\@initrds, ["initrd$efi $prefix/images/initrd.img"],
                'initrd uses the same transfer path');
            is(readlink("$bootdir/grub2-node"), "grub2.$loader_arch", 'node loader is published');
            for my $alias ('grub.cfg-C0000202', 'grub.cfg-01-02-00-00-00-00-02') {
                is(-f "$bootdir/$alias" ? read_text("$bootdir/$alias") : undef,
                    $config, "$alias publishes the node configuration");
            }
        };
    }
}

done_testing();
