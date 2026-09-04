#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use File::Spec;
use File::Temp qw(tempdir);
use Test::More;
use xCAT::DHCP::BootPolicy;

my ($dhcpd) = grep { -x $_ } qw(/usr/sbin/dhcpd /usr/local/sbin/dhcpd);
plan skip_all => 'dhcpd is required for ISC configuration validation' unless $dhcpd;
plan skip_all => 'root is required to validate from the ISC configuration directory'
  unless $> == 0;

my @config = (
    "#xCAT generated dhcp configuration\n",
    "\n",
    "option conf-file code 209 = text;\n",
    "option user-class-identifier code 77 = string;\n",
    "option client-architecture code 93 = unsigned integer 16;\n",
    "option www-server code 114 = string;\n",
    "default-lease-time 600;\n",
    "max-lease-time 600;\n",
    "subnet 192.0.2.0 netmask 255.255.255.0 {\n",
    "  range 192.0.2.100 192.0.2.110;\n",
);

ok(
    xCAT::DHCP::BootPolicy->ensure_isc_path_prefix_definition(\@config),
    'the upgrade path adds option 210 to an existing configuration',
);
push @config, @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
        next_server => '192.0.2.1',
        portsuffix  => '',
        net         => '192.0.2.0',
        prefix      => 24,
        s390x_qemu_config_present => 1,
    ) }, "}\n";

my $configuration_root = -d '/etc/dhcp' ? '/etc/dhcp' : '/etc';
my $directory = tempdir(DIR => $configuration_root, CLEANUP => 1);
my $path = File::Spec->catfile($directory, 'dhcpd.conf');
open(my $config_file, '>', $path) or die "Cannot create $path: $!";
print {$config_file} @config;
close($config_file) or die "Cannot close $path: $!";

my $status = system($dhcpd, '-t', '-cf', $path);
is($status, 0, 'ISC accepts the upgraded s390x boot policy');

done_testing();
