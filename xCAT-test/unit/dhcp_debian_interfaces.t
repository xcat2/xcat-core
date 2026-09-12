#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use File::Temp qw(tempdir);

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_dhcp_plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if ( -f $source_dhcp_plugin ) {
    require $source_dhcp_plugin;
} else {
    require xCAT_plugin::dhcp;
}

# What `makedhcp` writes into /etc/default/isc-dhcp-server matters for one
# reason: it decides which interfaces dhcpd is launched with. So assert that,
# not the name of any variable.
#
# isc-dhcp-server.service sources that file and expands one variable onto the
# command line, and which one changed with the package. Verified by unpacking
# the archive's own debs:
#
#   trusty  4.2.4-7ubuntu12       sysvinit only        INTERFACES
#   xenial  4.3.3-5ubuntu12       unit                 $INTERFACES
#   bionic  4.3.5-3ubuntu7        unit                 $INTERFACES
#   focal   4.4.1-2.1ubuntu5      unit                 $INTERFACES
#   jammy   4.4.1-2.3ubuntu2      unit                 $INTERFACESv4
#   noble   4.4.3-P1-4ubuntu2     unit                 $INTERFACESv4  (+ v6 unit)
#
# dhcpd given no interface argument does not fail: it binds every interface it
# can find. So the damage is silent -- a management node naming one provisioning
# NIC in site.dhcpinterfaces gets a daemon listening on all of them.

# The stock file as the package ships it on bionic and later.
my $stock = <<'EOF';
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)

# Path to dhcpd's config file (default: /etc/dhcp/dhcpd.conf).
#DHCPDv4_CONF=/etc/dhcp/dhcpd.conf

# On what interfaces should the DHCP server (dhcpd) serve DHCP requests?
INTERFACESv4=""
INTERFACESv6=""
EOF

# Expand a variable exactly as the systemd unit does: source the file in sh and
# print what would land on dhcpd's command line.
sub launched_with {
    my ($content, $variable) = @_;

    my $dir  = tempdir(CLEANUP => 1);
    my $path = "$dir/isc-dhcp-server";
    open(my $fh, '>', $path) or die "cannot write $path: $!";
    print $fh $content;
    close($fh);

    my $out = `sh -c '. "$path"; printf %s "\$$variable"' 2>/dev/null`;
    return defined($out) ? $out : '';
}

# Every release in support, the package it ships, and the variable its unit
# expands. This table is the contract: the writer has to satisfy every row.
my @RELEASES = (
    [ '16.04', '4.3.3-5ubuntu12',   'INTERFACES'   ],
    [ '18.04', '4.3.5-3ubuntu7',    'INTERFACES'   ],
    [ '20.04', '4.4.1-2.1ubuntu5',  'INTERFACES'   ],
    [ '22.04', '4.4.1-2.3ubuntu2',  'INTERFACESv4' ],
    [ '24.04', '4.4.3-P1-4ubuntu2', 'INTERFACESv4' ],
    [ '26.04', '4.4.3-P1-4ubuntu2', 'INTERFACESv4' ],
);

sub written_for {
    my ($version, $nics, $content) = @_;
    my @keys = xCAT_plugin::dhcp::debian_sysconfig_interface_keys($version);
    return xCAT_plugin::dhcp::_sysconfig_interfaces_content(
        defined($content) ? $content : $stock, [@keys], $nics);
}

# makedhcp is serving one provisioning NIC, named in site.dhcpinterfaces. On
# every release, that NIC has to be what dhcpd is launched with.
foreach my $release (@RELEASES) {
    my ($ubuntu, $version, $variable) = @{$release};

    my $written = written_for($version, ['eth1']);

    is( launched_with($written, $variable), 'eth1',
        "$ubuntu ($version): dhcpd is launched restricted to the interface xCAT serves" );

    isnt( launched_with($written, $variable), '',
        "$ubuntu ($version): dhcpd is not left to bind every interface on the machine" );

    # Serving several interfaces must reach the daemon as several interfaces.
    my $multi = written_for($version, ['eth1', 'eth2']);
    my @served = sort split /\s+/, launched_with($multi, $variable);
    is_deeply( \@served, ['eth1', 'eth2'],
        "$ubuntu ($version): every served interface reaches dhcpd" );

    # A remote (service node) interface is not something this daemon can bind.
    my $remote = written_for($version, ['eth1', '!remote!eth9']);
    unlike( launched_with($remote, $variable), qr/remote/,
        "$ubuntu ($version): a !remote! interface is not passed to the local daemon" );

    # The v6 unit takes $INTERFACES before 22.04 and $INTERFACESv6 after. Leaving
    # its variable empty is how dhcpd6, once enabled, ends up bound to everything.
    my $v6 = $variable eq 'INTERFACES' ? 'INTERFACES' : 'INTERFACESv6';
    is( launched_with($written, $v6), 'eth1',
        "$ubuntu ($version): the v6 unit is restricted to the same interfaces" );

    # A value the package's debconf prompt or an admin left behind has to lose
    # to site.dhcpinterfaces, or the setting is decoration.
    my $preset = $stock;
    $preset =~ s/^\Q$variable\E=.*$/$variable="eth0"/m
        or $preset .= qq{$variable="eth0"\n};
    my $overridden = written_for($version, ['eth1'], $preset);
    is( launched_with($overridden, $variable), 'eth1',
        "$ubuntu ($version): a value left by debconf is replaced" );

    # Whichever variable is not the one this release reads must still be left
    # alone, not claimed by a prefix match.
    foreach my $other (grep { $_ ne $variable } qw(INTERFACESv4 INTERFACESv6)) {
        next if ($written =~ m/^\s*\Q$other\E\s*=/m);
        fail("$ubuntu ($version): the $other line the package ships was removed");
    }
}

# With no package version to go on, err towards writing every spelling: an unset
# variable is what leaves dhcpd bound to everything.
foreach my $unknown (undef, '', 'none') {
    my @keys = xCAT_plugin::dhcp::debian_sysconfig_interface_keys($unknown);
    my $written = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
        $stock, [@keys], ['eth1']);
    foreach my $variable (qw(INTERFACES INTERFACESv4 INTERFACESv6)) {
        is( launched_with($written, $variable), 'eth1',
            'an unknown package version still restricts dhcpd, via ' . $variable );
    }
}

# ...and on every machine, not just one with no isc-dhcp-server. A writer that
# asks the local dpkg when handed no version answers differently on the build
# host than on the machine being configured.
{
    no warnings qw(redefine once);
    local *xCAT_plugin::dhcp::isc_dhcp_installed_version = sub {
        return '4.4.3-P1-4ubuntu2';
    };
    my @keys = xCAT_plugin::dhcp::debian_sysconfig_interface_keys(undef);
    my $written = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
        $stock, [@keys], ['eth1']);
    is( launched_with($written, 'INTERFACES'), 'eth1',
        'an unknown version is not silently replaced by the local package version' );
}

# Ordering of the package versions themselves. 20.04 and 22.04 both ship upstream
# 4.4.1 and differ only in the Debian revision.
is( xCAT_plugin::dhcp::_isc_dhcp_version_cmp('4.4.1-2.1ubuntu5', '4.4.1-2.3ubuntu2'), -1,
    '20.04 sorts below 22.04 despite sharing upstream 4.4.1' );
is( xCAT_plugin::dhcp::_isc_dhcp_version_cmp('4.4.3-P1-4ubuntu2', '4.4.1-2.3ubuntu2'), 1,
    '24.04 sorts above 22.04' );
is( xCAT_plugin::dhcp::_isc_dhcp_version_cmp('4.3.5-3ubuntu7', '4.4.1-2.3'), -1,
    '18.04 sorts below the split' );
is( xCAT_plugin::dhcp::_isc_dhcp_version_cmp('4.4.1-2.3ubuntu2', '4.4.1-2.3ubuntu2'), 0,
    'a version equals itself' );

# Debian's own packages have no systemd unit; the sysvinit script reads
# INTERFACESv4 and falls back to INTERFACES only when v4 is empty.
foreach my $debian ('4.4.1-2.3+deb11u2', '4.4.3-P1-2', '4.4.3-P1-8') {
    my $written = written_for($debian, ['eth1']);
    is( launched_with($written, 'INTERFACESv4'), 'eth1',
        "Debian $debian: dhcpd is launched restricted to the interface xCAT serves" );
}

# A node upgraded from an xCAT that wrote the wrong key has the damage on disk
# already: no INTERFACESv4 and two INTERFACES lines. Running makedhcp again has
# to repair that file, not add to it.
my $damaged = <<'EOF';
# Defaults for isc-dhcp-server (sourced by /etc/init.d/isc-dhcp-server)
INTERFACES="eth1"
INTERFACES="eth1"
EOF
my $repaired = written_for('4.4.3-P1-4ubuntu2', ['eth2'], $damaged);

is( launched_with($repaired, 'INTERFACESv4'), 'eth2',
    'a file left behind by an older xCAT is repaired' );

foreach my $key (qw(INTERFACESv4 INTERFACESv6)) {
    my $count = () = ($repaired =~ m/^\s*\Q$key\E\s*=/mg);
    is( $count, 1, "$key is assigned exactly once" );
}

# The EL and SLES paths pass a single key and must keep working unchanged.
my $el = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
    qq{# Command line options here\nDHCPDARGS=\n}, 'DHCPDARGS', ['eth1', 'eth2']);
is( launched_with($el, 'DHCPDARGS'), 'eth1 eth2',
    'the single-key sysconfig path is unchanged' );

done_testing();
