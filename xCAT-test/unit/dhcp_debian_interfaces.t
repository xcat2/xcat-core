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

# What `makedhcp` writes into /etc/default/isc-dhcp-server only matters for one
# reason: it decides which interfaces dhcpd is launched with. So assert that,
# not the name of any variable.
#
# On Ubuntu the daemon is started by isc-dhcp-server.service, which sources that
# file and expands one variable onto dhcpd's command line:
#
#   EnvironmentFile=/etc/default/isc-dhcp-server
#   ExecStart=/bin/sh -ec '... exec dhcpd ... -cf $CONFIG_FILE $INTERFACESv4'
#
# The variable it expands changed with the package. Verified by unpacking the
# archive's own debs:
#
#   trusty  4.2.4-7ubuntu12       sysvinit only        INTERFACES
#   xenial  4.3.3-5ubuntu12       unit                 $INTERFACES
#   bionic  4.3.5-3ubuntu7        unit                 $INTERFACES
#   focal   4.4.1-2.1ubuntu5      unit                 $INTERFACES
#   jammy   4.4.1-2.3ubuntu2      unit                 $INTERFACESv4
#   noble   4.4.3-P1-4ubuntu2     unit                 $INTERFACESv4  (+ v6 unit)
#
# and every package from bionic on ships a default file containing only
# INTERFACESv4/INTERFACESv6, seeded empty by postinst.
#
# dhcpd given no interface argument does not fail: it binds every interface it
# can find and ignores the ones with no subnet declaration. So the damage is
# silent. A management node whose site.dhcpinterfaces names one provisioning
# NIC gets a daemon listening on all of them, and the provisioning NIC is served
# only because makedhcp also wrote a subnet for it -- not because anything
# honoured the setting.

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

# makedhcp is serving one provisioning NIC, named in site.dhcpinterfaces.
my $written = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
    $stock, 'INTERFACES', ['eth1']);

is( launched_with($written, 'INTERFACESv4'), 'eth1',
    'dhcpd is launched restricted to the interface xCAT is serving' );

isnt( launched_with($written, 'INTERFACESv4'), '',
    'dhcpd is not left to bind every interface on the machine' );

# The stock file has no INTERFACES line, so a writer that targets the wrong
# variable does not merely fail to take effect -- its prefix match claims the
# INTERFACESv4 and INTERFACESv6 lines and overwrites both, removing the only
# variables the units read.
like( $written, qr/^\s*INTERFACESv4\s*=/m,
    'the INTERFACESv4 line the unit reads is still present' );
like( $written, qr/^\s*INTERFACESv6\s*=/m,
    'the INTERFACESv6 line the v6 unit reads is still present' );

# Serving several interfaces must reach the daemon as several interfaces.
my $multi = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
    $stock, 'INTERFACES', ['eth1', 'eth2']);
my @served = sort split /\s+/, launched_with($multi, 'INTERFACESv4');
is_deeply( \@served, ['eth1', 'eth2'],
    'every served interface reaches dhcpd' );

# A remote (service node) interface is not something this daemon can bind.
my $remote = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
    $stock, 'INTERFACES', ['eth1', '!remote!eth9']);
unlike( launched_with($remote, 'INTERFACESv4'), qr/remote/,
    'a !remote! interface is not passed to the local daemon' );

# An admin or the package's debconf prompt may already have set the variable.
# xCAT's list must win, or site.dhcpinterfaces is decoration.
my $preset = $stock;
$preset =~ s/INTERFACESv4=""/INTERFACESv4="eth0"/;
my $overridden = xCAT_plugin::dhcp::_sysconfig_interfaces_content(
    $preset, 'INTERFACES', ['eth1']);
is( launched_with($overridden, 'INTERFACESv4'), 'eth1',
    'a value left by debconf is replaced by the interfaces xCAT serves' );

done_testing();
