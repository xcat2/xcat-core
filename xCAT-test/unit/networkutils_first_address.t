#!/usr/bin/env perl
use strict;
use warnings;
## no critic (Modules::RequireFilenameMatchesPackage, TestingAndDebugging::ProhibitNoWarnings)

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

BEGIN {
    package NetworkUtilsTestCommand;
    our $ip_addr_output = '';

    package xCAT::Table;
    our @network_entries;
    sub new { return bless {}, shift; }
    sub getAllAttribs { return @network_entries; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub get_site_attribute {
        my ($attribute) = @_;
        return ('192.0.2.1') if $attribute eq 'master';
        return;
    }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package main;
    *CORE::GLOBAL::readpipe = sub {
        my ($command) = @_;
        return $NetworkUtilsTestCommand::ip_addr_output
          if $command eq '/sbin/ip addr';
        die "Unexpected command in NetworkUtils unit test: $command";
    };
}

require xCAT::NetworkUtils;

sub set_ip_addr_output {
    $NetworkUtilsTestCommand::ip_addr_output = join('', @_);
    @xCAT::Table::network_entries = ();
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

done_testing();
