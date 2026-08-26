#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use lib "$FindBin::Bin/../lib";
use File::Slurper qw(write_text);
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;
use XCAT::Test::File qw(repo_path);

BEGIN {
    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our ($tftpdir, $site_master, $site_httpport, %site_extra);
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute {
        my $attribute = $_[-1];
        return ($site_extra{$attribute}) if exists $site_extra{$attribute};
        return ($site_master) if $attribute eq 'master';
        return ($site_httpport) if $attribute eq 'httpport' and defined $site_httpport;
        return;
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    our ($normnet_addresses, $hexnet_addresses, @master_addresses);
    sub my_nets {
        die "mknb did not request all normalized-network addresses"
          unless $_[-1] eq 'all';
        return $normnet_addresses;
    }
    sub my_hexnets {
        die "mknb did not request all hexadecimal-network addresses"
          unless $_[-1] eq 'all';
        return $hexnet_addresses;
    }
    sub getipaddr { return @master_addresses; }
    our $nic_ips;
    sub get_nic_ip { return $nic_ips || {}; }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::noderange"} = sub { return; };
    }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

my $source_mknb_plugin = repo_path('xCAT-server/lib/xcat/plugins/mknb.pm');
require $source_mknb_plugin;

my ($legacy, $selected) = xCAT_plugin::mknb::_select_network_addresses(
    {
        '10.20.30.0/24' => [
            '10.20.30.10',
            '10.20.30.250',
        ],
    },
    ['10.20.30.250'],
);
is_deeply(
    $legacy,
    { '10.20.30.0/24' => '10.20.30.250' },
    'Linux HA keeps the last address as the legacy network address',
);
is_deeply(
    $selected,
    { '10.20.30.0/24' => '10.20.30.250' },
    'Linux HA selects the local site.master virtual address',
);

($legacy, $selected) = xCAT_plugin::mknb::_select_network_addresses(
    {
        '10.30.40.0/24' => [
            '10.30.40.20',
            '10.30.40.100',
        ],
    },
    ['192.0.2.1'],
);
is_deeply(
    $legacy,
    { '10.30.40.0/24' => '10.30.40.100' },
    'a service node keeps its last address as the legacy network address',
);
is_deeply(
    $selected,
    { '10.30.40.0/24' => '10.30.40.20' },
    'a service node ignores a remote site.master address and selects its first local address',
);

($legacy, $selected) = xCAT_plugin::mknb::_select_network_addresses(
    {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.168.149.100',
        ],
        '198.51.100.0/24' => [],
    },
    [],
);
is_deeply(
    $legacy,
    { '192.168.144.0/20' => '192.168.149.100' },
    'missing site.master preference preserves the last-address legacy value',
);
is_deeply(
    $selected,
    { '192.168.144.0/20' => '192.168.148.10' },
    'missing site.master preference falls back to the first candidate and skips empty networks',
);

sub prepare_tftpdir {
    my ($root, $name, $arch, $image_type) = @_;
    $image_type //= 'genesis';
    $xCAT::TableUtils::tftpdir = "$root/$name";
    make_path(
        "$xCAT::TableUtils::tftpdir/xcat",
        "$xCAT::TableUtils::tftpdir/etc",
    );
    my @files = ("$xCAT::TableUtils::tftpdir/xcat/genesis.kernel.$arch");
    if ($image_type eq 'legacy') {
        push @files,
          "$xCAT::TableUtils::tftpdir/xcat/nbk.$arch",
          "$xCAT::TableUtils::tftpdir/xcat/nbfs.$arch.gz";
    } else {
        push @files, "$xCAT::TableUtils::tftpdir/xcat/genesis.fs.$arch.gz";
    }
    foreach my $file (@files) {
        open(my $fh, '>', $file) or die "Unable to create $file: $!";
        close($fh);
    }
}

sub run_mknb {
    my ($arch) = @_;
    my @responses;
    xCAT_plugin::mknb::process_request(
        { arg => [$arch, '--configfileonly'] },
        sub { push @responses, @_; },
    );
    return \@responses;
}

sub read_config {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

sub generation_succeeded {
    my ($responses, $description) = @_;
    ok(
        !grep({ ref($_) eq 'HASH' && $_->{error} } @{$responses}),
        $description,
    );
}

sub use_reporter_address_maps {
    $xCAT::NetworkUtils::normnet_addresses = {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.168.149.100',
        ],
    };
    $xCAT::NetworkUtils::hexnet_addresses = {
        c0a89 => [
            '192.168.148.10',
            '192.168.149.100',
        ],
    };
    $xCAT::TableUtils::site_master = 'master.example.com';
    @xCAT::NetworkUtils::master_addresses = ('203.0.113.10');
}

my $tmpdir = tempdir(CLEANUP => 1);
$::XCATROOT = "$tmpdir/xcatroot";
make_path(
    "$::XCATROOT/share/xcat/netboot/genesis/x86_64",
    "$::XCATROOT/share/xcat/netboot/genesis/ppc64",
);

use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-x86', 'x86_64');
my $responses = run_mknb('x86_64');
generation_succeeded($responses, 'x86 configuration generation succeeds');

my $genesis_pxe = read_config(
    "$xCAT::TableUtils::tftpdir/pxelinux.cfg/C0A89"
);
like(
    $genesis_pxe,
    qr/^  KERNEL xcat\/genesis\.kernel\.x86_64$/m,
    'PXELINUX selects the Genesis kernel',
);
like(
    $genesis_pxe,
    qr/^  APPEND initrd=xcat\/genesis\.fs\.x86_64\.gz /m,
    'PXELINUX makes the Genesis initramfs relative to the configured TFTP root',
);
unlike(
    $genesis_pxe,
    qr/\Q$xCAT::TableUtils::tftpdir\E/,
    'PXELINUX does not expose the configured TFTP root',
);

foreach my $relative_path (
    'xcat/xnba/nets/192.168.144.0_20',
    'pxelinux.cfg/C0A89',
) {
    my $content = read_config("$xCAT::TableUtils::tftpdir/$relative_path");
    like(
        $content,
        qr/xcatd=192\.168\.148\.10:3001/,
        "$relative_path uses the first address as the xcatd endpoint",
    );
    unlike(
        $content,
        qr/xcatd=192\.168\.149\.100:3001/,
        "$relative_path does not use the later floating address as the xcatd endpoint",
    );
}

use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-x86-legacy', 'x86_64', 'legacy');
$responses = run_mknb('x86_64');
generation_succeeded($responses, 'legacy x86 configuration generation succeeds');

my $legacy_pxe = read_config(
    "$xCAT::TableUtils::tftpdir/pxelinux.cfg/C0A89"
);
like(
    $legacy_pxe,
    qr/^  KERNEL xcat\/nbk\.x86_64$/m,
    'PXELINUX keeps the legacy kernel',
);
like(
    $legacy_pxe,
    qr/^  APPEND initrd=xcat\/nbfs\.x86_64\.gz /m,
    'PXELINUX keeps the legacy initramfs path',
);

use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-power', 'ppc64');
$responses = run_mknb('ppc64');
generation_succeeded($responses, 'POWER configuration generation succeeds');

foreach my $relative_path (
    'pxelinux.cfg/p/192.168.144.0_20',
    'etc/c0a89',
) {
    my $content = read_config("$xCAT::TableUtils::tftpdir/$relative_path");
    like(
        $content,
        qr/kernel http:\/\/192\.168\.148\.10\//,
        "$relative_path uses the first address for the kernel URL",
    );
    like(
        $content,
        qr/initrd http:\/\/192\.168\.148\.10\//,
        "$relative_path uses the first address for the initrd URL",
    );
    like(
        $content,
        qr/xcatd=192\.168\.148\.10:3001/,
        "$relative_path uses the first address as the xcatd endpoint",
    );
    unlike(
        $content,
        qr/(?:kernel|initrd) http:\/\/192\.168\.149\.100\/|xcatd=192\.168\.149\.100:3001/,
        "$relative_path has no functional endpoint using the later floating address",
    );
}

# the default HTTP port is left out of the generated URLs, but a port that is
# not the default still has to be carried through
$xCAT::TableUtils::site_httpport = '8080';
use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-power-altport', 'ppc64');
$responses = run_mknb('ppc64');
generation_succeeded($responses, 'POWER configuration generation succeeds with a non-default HTTP port');

my $altport_content = read_config("$xCAT::TableUtils::tftpdir/pxelinux.cfg/p/192.168.144.0_20");
like(
    $altport_content,
    qr/kernel http:\/\/192\.168\.148\.10:8080\//,
    'a non-default HTTP port is kept in the kernel URL',
);
like(
    $altport_content,
    qr/initrd http:\/\/192\.168\.148\.10:8080\//,
    'a non-default HTTP port is kept in the initrd URL',
);
$xCAT::TableUtils::site_httpport = undef;

$xCAT::NetworkUtils::normnet_addresses = {
    '192.168.144.0/20' => ['192.168.148.10'],
};
$xCAT::NetworkUtils::hexnet_addresses = {
    c0a89 => ['192.168.148.10'],
};
$xCAT::TableUtils::site_master = 'master.example.com';
@xCAT::NetworkUtils::master_addresses = ('203.0.113.10');
prepare_tftpdir($tmpdir, 'tftpboot-no-floating', 'x86_64');
$responses = run_mknb('x86_64');
generation_succeeded($responses, 'configuration generation without a floating address succeeds');
my $no_floating_xnba = read_config(
    "$xCAT::TableUtils::tftpdir/xcat/xnba/nets/192.168.144.0_20"
);
my $no_floating_pxe = read_config(
    "$xCAT::TableUtils::tftpdir/pxelinux.cfg/C0A89"
);

$xCAT::TableUtils::site_master = undef;
@xCAT::NetworkUtils::master_addresses = ();
prepare_tftpdir($tmpdir, 'tftpboot-no-floating', 'x86_64');
$responses = run_mknb('x86_64');
generation_succeeded($responses, 'configuration generation without site.master succeeds');
is(
    read_config("$xCAT::TableUtils::tftpdir/xcat/xnba/nets/192.168.144.0_20"),
    $no_floating_xnba,
    'xNBA output is byte-identical without a site.master preference',
);
is(
    read_config("$xCAT::TableUtils::tftpdir/pxelinux.cfg/C0A89"),
    $no_floating_pxe,
    'legacy PXE output is byte-identical without a site.master preference',
);

# riscv64 discovery boots through UEFI firmware and grub2: mknb writes one
# grub2 configuration per network, named by the network's hex prefix the same
# way PXELINUX files are, instead of PXELINUX/xNBA or petitboot files.
make_path("$::XCATROOT/share/xcat/netboot/genesis/riscv64");
use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-riscv64', 'riscv64');
$responses = run_mknb('riscv64');
generation_succeeded($responses, 'riscv64 configuration generation succeeds');

my $grub_cfg_path = "$xCAT::TableUtils::tftpdir/boot/grub2/grub.cfg-C0A89";
ok(-f $grub_cfg_path, 'riscv64 writes a grub2 configuration named by the network hex prefix');
my $grub_cfg = read_config($grub_cfg_path);
like(
    $grub_cfg,
    qr/^# xCAT Genesis discovery for network C0A89 - generated by mknb, do not edit$/m,
    'the grub2 discovery configuration names its network and generator',
);
like($grub_cfg, qr/^set default=0$/m, 'the grub2 discovery configuration selects the first entry');
like($grub_cfg, qr/^set timeout=5$/m, 'the grub2 discovery configuration boots after a short timeout');
like($grub_cfg, qr/^set fallback=1$/m, 'a payload that cannot be fetched over HTTP falls back to the TFTP entry');
like(
    $grub_cfg,
    qr/^if \[ "\$grub_cpu" = "riscv64" \]; then$/m,
    'the riscv64 menu entry is guarded by the GRUB cpu',
);
like($grub_cfg, qr/^menuentry "xCAT Genesis riscv64" \{$/m, 'the menu entry names the architecture');
like(
    $grub_cfg,
    qr/^    linux \Q$xCAT::TableUtils::tftpdir\E\/xcat\/genesis\.kernel\.riscv64 xcatd=192\.168\.148\.10:3001 BOOTIF=\$net_default_mac$/m,
    'the kernel line loads the Genesis kernel with the xcatd endpoint and the booting MAC',
);
like(
    $grub_cfg,
    qr/^    initrd \Q$xCAT::TableUtils::tftpdir\E\/xcat\/genesis\.fs\.riscv64\.gz$/m,
    'the initrd line loads the Genesis initramfs',
);

# the Genesis payload is large and TFTP serves one client at a time, so the default
# entry fetches it over HTTP and the TFTP entry stays behind it
like($grub_cfg, qr/^    set root=http,192\.168\.148\.10$/m, 'the default entry fetches the payload over HTTP');
like($grub_cfg, qr/^    insmod http$/m, 'the HTTP entry loads the grub2 http module');
my ($first_entry) = $grub_cfg =~ /^(menuentry .*?^\})/ms;
like($first_entry || '', qr/set root=http,/, 'the first, default entry is the HTTP one');
like($grub_cfg, qr/^menuentry "xCAT Genesis riscv64 \(TFTP\)" \{$/m, 'a TFTP entry follows it');
like(
    $grub_cfg,
    qr/^menuentry "xCAT Genesis riscv64 \(TFTP\)" \{\n    insmod tftp\n    set root=tftp,192\.168\.148\.10\n    linux \/xcat\/genesis\.kernel\.riscv64 xcatd=192\.168\.148\.10:3001 BOOTIF=\$net_default_mac\n    initrd \/xcat\/genesis\.fs\.riscv64\.gz\n\}$/m,
    'the TFTP entry keeps the paths relative to the TFTP root',
);
like($grub_cfg, qr/^\}\nfi\n\z/m, 'the configuration closes the menu entries and the cpu guard');
unlike(
    $grub_cfg,
    qr/xcatd=192\.168\.149\.100:3001/,
    'the grub2 configuration does not use the later floating address as the xcatd endpoint',
);
ok(!-e "$xCAT::TableUtils::tftpdir/pxelinux.cfg/C0A89", 'riscv64 writes no PXELINUX configuration');
ok(!-e "$xCAT::TableUtils::tftpdir/xcat/xnba", 'riscv64 writes no xNBA configuration');
ok(!-e "$xCAT::TableUtils::tftpdir/etc/c0a89", 'riscv64 writes no petitboot configuration');
ok(!-e "$xCAT::TableUtils::tftpdir/pxelinux.cfg/p", 'riscv64 writes no POWER network configuration');
is_deeply(
    [ xCAT_plugin::mknb::_grub2_discovery_arches($xCAT::TableUtils::tftpdir) ],
    [ [ 'riscv64', 'riscv64', 'xcat/genesis.kernel.riscv64', 'xcat/genesis.fs.riscv64.gz' ] ],
    'the published riscv64 Genesis artifacts are enumerated relative to the TFTP root',
);

# serial console settings reach the Genesis kernel line
%xCAT::TableUtils::site_extra = (
    defserialport  => '0',
    defserialspeed => '115200',
    defserialflow  => 'hard',
    xcatdport      => '3002',
);
$responses = run_mknb('riscv64');
generation_succeeded($responses, 'riscv64 configuration generation succeeds with a serial console');
like(
    read_config($grub_cfg_path),
    qr/^    linux \Q$xCAT::TableUtils::tftpdir\E\/xcat\/genesis\.kernel\.riscv64 xcatd=192\.168\.148\.10:3002 console=tty0 console=ttyS0,115200n8r BOOTIF=\$net_default_mac$/m,
    'the serial console and a non-default xcatd port are carried into the kernel line',
);
%xCAT::TableUtils::site_extra = ();

# a non-default site.httpport reaches the HTTP entry
%xCAT::TableUtils::site_extra = ( httpport => '8080' );
$responses = run_mknb('riscv64');
generation_succeeded($responses, 'riscv64 configuration generation succeeds with a non-default HTTP port');
like(
    read_config($grub_cfg_path),
    qr/^    set root=http,192\.168\.148\.10:8080$/m,
    'the HTTP entry uses the configured HTTP port',
);
like(
    read_config($grub_cfg_path),
    qr/^    set root=tftp,192\.168\.148\.10$/m,
    'the TFTP entry is unaffected by the HTTP port',
);
%xCAT::TableUtils::site_extra = ();

# an lzma initramfs is preferred when mknb produced one
write_text(
    "$xCAT::TableUtils::tftpdir/xcat/genesis.fs.riscv64.lzma", ''
);
$responses = run_mknb('riscv64');
generation_succeeded($responses, 'riscv64 configuration generation succeeds with an lzma initramfs');
like(
    read_config($grub_cfg_path),
    qr/^    initrd \Q$xCAT::TableUtils::tftpdir\E\/xcat\/genesis\.fs\.riscv64\.lzma$/m,
    'the lzma Genesis initramfs is preferred over the gzip one',
);
unlink("$xCAT::TableUtils::tftpdir/xcat/genesis.fs.riscv64.lzma");

# the discovery configurations are only reachable through grub2.<arch>, which mknb does not
# build: a missing boot loader is reported instead of failing silently in firmware
{
    my $loader = "$xCAT::TableUtils::tftpdir/boot/grub2/grub2.riscv64";
    my $missing = run_mknb('riscv64');
    generation_succeeded($missing, 'riscv64 configuration generation succeeds without the grub2 boot loader');
    ok(
        scalar(grep { ref($_) eq 'HASH' && $_->{data} && "@{$_->{data}}" =~ m{\Qboot/grub2/grub2.riscv64\E is missing} } @{$missing}),
        'a missing grub2.riscv64 boot loader is reported',
    );
    make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
    write_text( $loader, '' );
    my $present = run_mknb('riscv64');
    ok(
        !grep({ ref($_) eq 'HASH' && $_->{data} && "@{$_->{data}}" =~ /is missing/ } @{$present}),
        'nothing is reported once the boot loader is in place',
    );
    unlink($loader);
}


# the configuration is rebuilt from what is published: without artifacts it goes away
unlink("$xCAT::TableUtils::tftpdir/xcat/genesis.kernel.riscv64");
is(
    xCAT_plugin::mknb::_write_grub2_discovery_config(
        tftpdir       => $xCAT::TableUtils::tftpdir,
        hexnet        => 'c0a89',
        xcatd_address => '192.168.148.10',
        xcatdport     => 3001,
    ),
    undef,
    'no grub2 discovery configuration is written without a published Genesis kernel',
);
ok(!-e $grub_cfg_path, 'a stale grub2 discovery configuration is removed with its artifacts');

# --configfileonly without published artifacts fails like the other architectures
$xCAT::TableUtils::tftpdir = "$tmpdir/tftpboot-riscv64-empty";
make_path("$xCAT::TableUtils::tftpdir/xcat");
$responses = run_mknb('riscv64');
ok(
    scalar(grep { ref($_) eq 'HASH' && $_->{error} && "@{$_->{error}}" =~ /No kernel file found/ } @{$responses}),
    'riscv64 --configfileonly without a kernel reports the missing kernel',
);

# a :noboot interface keeps no discovery configuration for its network
%xCAT::TableUtils::site_extra = ( dhcpinterfaces => 'eth0,eth1:noboot' );
$xCAT::NetworkUtils::nic_ips = { eth0 => '10.0.0.1', eth1 => '192.168.148.10' };
use_reporter_address_maps();
prepare_tftpdir($tmpdir, 'tftpboot-riscv64-noboot', 'riscv64');
make_path("$xCAT::TableUtils::tftpdir/boot/grub2");
write_text(
    "$xCAT::TableUtils::tftpdir/boot/grub2/grub.cfg-C0A89", ''
);
$responses = run_mknb('riscv64');
generation_succeeded($responses, 'riscv64 configuration generation succeeds with a :noboot interface');
ok(
    !-e "$xCAT::TableUtils::tftpdir/boot/grub2/grub.cfg-C0A89",
    'a network served by a :noboot interface gets no grub2 discovery configuration',
);
%xCAT::TableUtils::site_extra = ();
$xCAT::NetworkUtils::nic_ips = undef;

done_testing();
