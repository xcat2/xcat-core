#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use xCAT::DHCP::BootPolicy;

my ($dhcpd) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
plan skip_all => 'dhcpd is required for ISC configuration validation' unless $dhcpd;
plan skip_all => 'root is required to validate from the ISC configuration directory'
  unless $> == 0;

$ENV{XCATCFG} ||= 'SQLite:/tmp';
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
if (-f $plugin) { require $plugin } else { require xCAT_plugin::dhcp }

my @header = (
    "#xCAT generated dhcp configuration\n",
    "\n",
    "option conf-file code 209 = text;\n",
    "option space gpxe;\n",
    "option gpxe-encap-opts code 175 = encapsulate gpxe;\n",
    "option gpxe.bus-id code 177 = string;\n",
    @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() },
    "option user-class-identifier code 77 = string;\n",
    "option client-architecture code 93 = unsigned integer 16;\n",
    "option www-server code 114 = string;\n",
    "default-lease-time 600;\n",
    "max-lease-time 600;\n",
);

# makedhcp without -n adds the iPXE feature options to the header that an older makedhcp -n wrote.
my %feature = map { $_ => 1 } @{ xCAT::DHCP::BootPolicy->isc_ipxe_feature_option_lines() };
my @upgraded = grep { !$feature{$_} } @header;
my @indented = map { /^option / ? "  $_" : $_ } @upgraded;
xCAT::DHCP::BootPolicy->isc_declare_ipxe_features($_) for \@upgraded, \@indented;

my @subnet = (
    "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
    "  range 192.0.2.100 192.0.2.110;\n",
    @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
            next_server => '192.0.2.1',
            portsuffix  => '',
            net         => '192.0.2.0',
            prefix      => 24,
        ) },
    "}\n",
);

# The PXE class names all three lease bounds rather than a maximum alone.
# dhcpd is the only thing that can say whether it accepts them in class scope.
push @subnet, @{ xCAT::DHCP::BootPolicy->isc_pxe_lease_class_lines() };

my $configuration_root = -d '/etc/dhcp' ? '/etc/dhcp' : '/etc';
my $directory = tempdir(DIR => $configuration_root, CLEANUP => 1);
for my $case ( [ 'a new configuration', \@header ], [ 'an upgraded configuration', \@upgraded ],
    [ 'an upgraded configuration with indented declarations', \@indented ] )
{
    my ( $label, $lines ) = @$case;
    my $path = File::Spec->catfile($directory, 'dhcpd.conf');
    open(my $config_file, '>', $path) or die "Cannot create $path: $!";
    print {$config_file} @$lines, @subnet;
    close($config_file) or die "Cannot close $path: $!";

    my $status = system($dhcpd, '-t', '-cf', $path);
    is($status, 0, "ISC accepts the boot policy and the PXE lease class in $label");
}

my $path = File::Spec->catfile($directory, 'ddns.conf');

for my $subnet_case (
    [ '4', 'subnet 192.0.2.0 netmask 255.255.255.0', '2.0.192.in-addr.arpa.' ],
    [ '6', 'subnet6 2001:db8::/64', '8.b.d.0.1.0.0.2.ip6.arpa.' ],
) {
    my ($family, $subnet, $reverse) = @{$subnet_case};
    for my $server_case (
        [ '2001:db8::53', 'primary6' ],
        [ '::ffff:192.0.2.53', 'primary6' ],
        [ '192.0.2.53', 'primary' ],
    ) {
        my ($server, $keyword) = @{$server_case};
        for my $enabled (0, 1) {
            my $zones = join '', xCAT_plugin::dhcp::isc_ddns_zone_statements(
                enabled    => $enabled,
                domain     => 'example.test.',
                ddnsdomain => 'nodes.example.test',
                server     => $server,
                key_name   => 'custom_key',
                zones      => [$reverse],
            );
            my $label = "DHCPv$family, DNS $server, DDNS $enabled";
            if ($enabled) {
                for my $zone ('nodes.example.test.', $reverse) {
                    like($zones, qr/zone \Q$zone\E \{\s*\Q$keyword $server; key custom_key;\E\s*\}/,
                        "$label: $zone uses the DNS server family and selected key");
                }
            } else {
                is($zones, '', "$label: no DDNS statements");
            }
            open(my $fh, '>', $path) or die "Cannot create $path: $!";
            print {$fh} "ddns-update-style interim;\n",
                "key custom_key { algorithm hmac-sha256; secret \"dGVzdA==\"; };\n",
                "$subnet {\n", $zones, "}\n";
            close($fh) or die "Cannot close $path: $!";
            is(system($dhcpd, "-$family", '-t', '-cf', $path), 0,
                "$label: ISC accepts the rendered configuration");
        }
    }
}

done_testing();
