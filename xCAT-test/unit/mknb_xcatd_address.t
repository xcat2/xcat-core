#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoStrict, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use File::Path qw(make_path);
use File::Temp qw(tempdir);
use Test::More;

BEGIN {
    package xCAT::Utils;
    $INC{'xCAT/Utils.pm'} = __FILE__;

    package xCAT::TableUtils;
    our ($tftpdir, $site_master);
    sub getTftpDir { return $tftpdir; }
    sub get_site_attribute {
        my $attribute = $_[-1];
        return ($site_master) if $attribute eq 'master';
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
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::NodeRange;
    sub import {
        my $caller = caller;
        no strict 'refs';
        *{"${caller}::noderange"} = sub { return; };
    }
    $INC{'xCAT/NodeRange.pm'} = __FILE__;
}

my $source_mknb_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/mknb.pm";
if (-f $source_mknb_plugin) {
    require $source_mknb_plugin;
} else {
    require xCAT_plugin::mknb;
}

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
    my ($root, $name, $arch) = @_;
    $xCAT::TableUtils::tftpdir = "$root/$name";
    make_path(
        "$xCAT::TableUtils::tftpdir/xcat",
        "$xCAT::TableUtils::tftpdir/etc",
    );
    foreach my $file (
        "$xCAT::TableUtils::tftpdir/xcat/genesis.kernel.$arch",
        "$xCAT::TableUtils::tftpdir/xcat/genesis.fs.$arch.gz",
    ) {
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
        qr/kernel http:\/\/192\.168\.148\.10:80\//,
        "$relative_path uses the first address for the kernel URL",
    );
    like(
        $content,
        qr/initrd http:\/\/192\.168\.148\.10:80\//,
        "$relative_path uses the first address for the initrd URL",
    );
    like(
        $content,
        qr/xcatd=192\.168\.148\.10:3001/,
        "$relative_path uses the first address as the xcatd endpoint",
    );
    unlike(
        $content,
        qr/(?:kernel|initrd) http:\/\/192\.168\.149\.100:80\/|xcatd=192\.168\.149\.100:3001/,
        "$relative_path has no functional endpoint using the later floating address",
    );
}

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

done_testing();
