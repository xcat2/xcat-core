#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

BEGIN {
    package NetworkUtilsTestCommand;
    our $ip_addr_output      = '';
    our $aix_ifconfig_output = '';

    package xCAT::Table;
    our @network_entries;
    sub new { return bless {}, shift; }
    sub getAllAttribs { return @network_entries; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub get_site_attribute {
        my $attribute = $_[-1];
        return ('192.0.2.1') if $attribute eq 'master';
        return;
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package main;
    *CORE::GLOBAL::readpipe = sub {
        my ($command) = @_;
        return $NetworkUtilsTestCommand::ip_addr_output
          if $command eq '/sbin/ip addr';
        return $NetworkUtilsTestCommand::aix_ifconfig_output
          if $command eq '/usr/sbin/ifconfig -a';
        die "Unexpected command in NetworkUtils unit test: $command";
    };
}

require xCAT::NetworkUtils;

sub set_ip_addr_output {
    $NetworkUtilsTestCommand::ip_addr_output = join('', @_);
    @xCAT::Table::network_entries = ();
}

sub set_aix_ifconfig_output {
    $NetworkUtilsTestCommand::aix_ifconfig_output = join('', @_);
    @xCAT::Table::network_entries = ();
}

sub run_as_aix {
    my ($code) = @_;
    local $^O = 'aix';
    return $code->();
}

set_ip_addr_output(
    "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
    "    inet 192.168.148.10/20 brd 192.168.159.255 scope global eth0\n",
    "       valid_lft forever preferred_lft forever\n",
    "    inet 192.168.149.100/20 scope global secondary eth0\n",
    "       valid_lft forever preferred_lft forever\n",
    "    inet6 2001:db8:1::10/64 scope global\n",
);

is_deeply(
    xCAT::NetworkUtils->my_nets(),
    { '192.168.144.0/20' => '192.168.149.100' },
    'my_nets default behavior remains last-address-wins',
);
is_deeply(
    xCAT::NetworkUtils->my_nets('all'),
    {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.168.149.100',
        ],
    },
    'my_nets all mode preserves every address in operating-system order',
);
is_deeply(
    xCAT::NetworkUtils->my_hexnets(),
    { c0a89 => '192.168.149.100' },
    'my_hexnets default behavior remains last-address-wins',
);
is_deeply(
    xCAT::NetworkUtils->my_hexnets('all'),
    {
        c0a89 => [
            '192.168.148.10',
            '192.168.149.100',
        ],
    },
    'my_hexnets all mode preserves every address in operating-system order',
);

set_ip_addr_output(
    "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
    "    inet 192.168.148.10/20 brd 192.168.159.255 scope global eth0\n",
    "    inet6 2001:db8:1::10/64 scope global\n",
);

is_deeply(
    xCAT::NetworkUtils->my_nets(),
    { '192.168.144.0/20' => '192.168.148.10' },
    'my_nets default output is unchanged when there is no floating address',
);
is_deeply(
    xCAT::NetworkUtils->my_nets('all'),
    { '192.168.144.0/20' => ['192.168.148.10'] },
    'my_nets all mode returns one candidate when there is no floating address',
);
is_deeply(
    xCAT::NetworkUtils->my_hexnets(),
    { c0a89 => '192.168.148.10' },
    'my_hexnets default output is unchanged when there is no floating address',
);
is_deeply(
    xCAT::NetworkUtils->my_hexnets('all'),
    { c0a89 => ['192.168.148.10'] },
    'my_hexnets all mode returns one candidate when there is no floating address',
);
is_deeply(
    xCAT::NetworkUtils->my_nets('all'),
    { '192.168.144.0/20' => ['192.168.148.10'] },
    'Linux IPv6 addresses remain outside the all-address result',
);

set_ip_addr_output(
    "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
    "    inet 192.168.148.10/20 brd 192.168.159.255 scope global eth0\n",
    "    inet 192.168.148.10/20 brd 192.168.159.255 scope global eth0\n",
);

is_deeply(
    xCAT::NetworkUtils->my_nets('all'),
    {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.168.148.10',
        ],
    },
    'my_nets all mode retains duplicate addresses',
);
is_deeply(
    xCAT::NetworkUtils->my_hexnets('all'),
    {
        c0a89 => [
            '192.168.148.10',
            '192.168.148.10',
        ],
    },
    'my_hexnets all mode retains duplicate addresses',
);

set_ip_addr_output(
    "2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500\n",
    "    inet 192.168.148.10/20 brd 192.168.159.255 scope global eth0\n",
);
@xCAT::Table::network_entries = (
    {
        net       => '192.168.144.0',
        mgtifname => '!remote!',
        mask      => '255.255.240.0',
    },
    {
        net       => '192.168.144.0',
        mgtifname => '!remote!',
        mask      => '255.255.240.0',
    },
    {
        net       => '198.51.100.0',
        mgtifname => '!remote!',
        mask      => '255.255.255.0',
    },
);

is_deeply(
    xCAT::NetworkUtils->my_nets(),
    {
        '192.168.144.0/20' => '192.0.2.1',
        '198.51.100.0/24'  => '192.0.2.1',
    },
    'remote networks keep overwriting earlier addresses in default mode',
);
is_deeply(
    xCAT::NetworkUtils->my_nets('all'),
    {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.0.2.1',
            '192.0.2.1',
        ],
        '198.51.100.0/24' => ['192.0.2.1'],
    },
    'remote networks append in table order and retain duplicates in all mode',
);

set_ip_addr_output();
is(
    xCAT::NetworkUtils->my_nets(),
    undef,
    'my_nets default mode remains undefined when no addresses exist',
);
is(
    xCAT::NetworkUtils->my_nets('all'),
    undef,
    'my_nets all mode remains undefined when no addresses exist',
);
is(
    xCAT::NetworkUtils->my_hexnets(),
    undef,
    'my_hexnets default mode remains undefined when no addresses exist',
);
is(
    xCAT::NetworkUtils->my_hexnets('all'),
    undef,
    'my_hexnets all mode remains undefined when no addresses exist',
);

set_aix_ifconfig_output(
    "en0: flags=1e080863,480<UP,BROADCAST,NOTRAILERS,RUNNING,SIMPLEX,MULTICAST,GROUPRT,64BIT,CHECKSUM_OFFLOAD(ACTIVE),CHAIN>\n",
    "        inet 192.168.148.10 netmask 0xfffff000 broadcast 192.168.159.255\n",
    "        inet 192.168.149.100 netmask 0xfffff000 broadcast 192.168.159.255\n",
    "        inet6 2001:db8:1::10/64\n",
    "        inet6 2001:db8:1::10/64\n",
);

is_deeply(
    run_as_aix(sub { xCAT::NetworkUtils->my_nets() }),
    {
        '192.168.144.0/20'   => '192.168.149.100',
        '2001:db8:1::10/64' => '2001:db8:1::10',
    },
    'AIX default mode keeps scalar last-address behavior for IPv4 and IPv6',
);
is_deeply(
    run_as_aix(sub { xCAT::NetworkUtils->my_nets('all') }),
    {
        '192.168.144.0/20' => [
            '192.168.148.10',
            '192.168.149.100',
        ],
        '2001:db8:1::10/64' => [
            '2001:db8:1::10',
            '2001:db8:1::10',
        ],
    },
    'AIX all mode preserves IPv4 order and retains duplicate IPv6 addresses',
);

done_testing();
