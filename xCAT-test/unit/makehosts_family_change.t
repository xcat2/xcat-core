#!/usr/bin/env perl
#
# makehosts for a node whose hosts.ip moved to the other address family kept the old line. With
# both "192.0.2.10 node01" and "2001:db8::10 node01" in /etc/hosts, node_address_family answers 4
# and nodeset renders an IPv4 install for a node the administrator moved to IPv6.
#
# A dual-stack node also has one line of each family, written by hand, and makehosts must keep it.
# The two are told apart by what is already there: a node with no line of the family being written
# changed family, and a node that has one is dual-stack.
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/hosts.pm";

no warnings qw(once redefine);
local *xCAT_plugin::hosts::getIPdomain = sub { return ( 'example.com', 'net' ); };

my %table_rows;
local *xCAT::Table::new = sub {
    my ( $class, $name ) = @_;
    return bless { name => $name }, 'xCAT::Table';
};
local *xCAT::Table::getNodesAttribs = sub { return \%table_rows; };

my $quiet = sub { return; };

# makehosts <noderange>: add_hosts_content reads hosts.ip through the table.
sub makehosts_node {
    my ( $lines, $node, $ip ) = @_;
    %table_rows = ( $node => [ { node => $node, ip => $ip } ] );
    my $entries = xCAT_plugin::hosts::_set_host_lines($lines);
    xCAT_plugin::hosts::add_hosts_content(
        nodelist => [$node],
        callback => $quiet,
        delnode  => 0,
        domain   => 'example.com'
    );
    return [ grep { /\S/ } @{$entries} ];
}

# makehosts with no noderange: add_all_hosts_content reads every hosts row.
sub makehosts_all {
    my ( $lines, @rows ) = @_;
    my $entries = xCAT_plugin::hosts::_set_host_lines($lines);
    xCAT_plugin::hosts::add_all_hosts_content(
        hostents => \@rows,
        callback => $quiet,
        domain   => 'example.com'
    );
    return [ grep { /\S/ } @{$entries} ];
}

is_deeply(
    makehosts_node(
        [ "192.0.2.10 node01 node01.example.com \n", "192.0.2.11 node02 node02.example.com \n" ],
        'node01', '2001:db8::10'
    ),
    [ "2001:db8::10 node01 node01.example.com \n", "192.0.2.11 node02 node02.example.com \n" ],
    'makehosts <node> replaces the IPv4 line of a node moved to IPv6'
);

is_deeply(
    makehosts_node( [ "2001:db8::10 node01 node01.example.com \n" ], 'node01', '192.0.2.10' ),
    [ "192.0.2.10 node01 node01.example.com \n" ],
    'makehosts <node> replaces the IPv6 line of a node moved to IPv4'
);

is_deeply(
    makehosts_all(
        [ "192.0.2.10 node01 node01.example.com \n" ],
        { node => 'node01', ip => '2001:db8::10' }
    ),
    [ "2001:db8::10 node01 node01.example.com \n" ],
    'makehosts with no noderange replaces the IPv4 line of a node moved to IPv6'
);

# Dual-stack: a line of the family being written exists, so the other one stays.
is_deeply(
    makehosts_node(
        [ "192.0.2.10 node01 node01.example.com \n", "2001:db8::10 node01 node01.example.com \n" ],
        'node01', '2001:db8::20'
    ),
    [ "192.0.2.10 node01 node01.example.com \n", "2001:db8::20 node01 node01.example.com \n" ],
    'a dual-stack node keeps its IPv4 line when its IPv6 address changes'
);

is_deeply(
    makehosts_node(
        [ "192.0.2.10 node01 node01.example.com \n", "2001:db8::10 node01 node01.example.com \n" ],
        'node01', '192.0.2.10'
    ),
    [ "192.0.2.10 node01 node01.example.com \n", "2001:db8::10 node01 node01.example.com \n" ],
    'a dual-stack node keeps its IPv6 line when makehosts writes its IPv4 address'
);

# makehosts -m adds a link-local line beside the node's address. That path calls addnode
# directly and must not replace the IPv4 line.
{
    my $entries = xCAT_plugin::hosts::_set_host_lines( [ "192.0.2.10 node01 node01.example.com \n" ] );
    xCAT_plugin::hosts::addnode( $quiet, 'node01', 'fe80::5054:ff:feaa:bbcc', 'node01', 'example.com' );
    is( scalar( grep { /^192\.0\.2\.10 / } @{$entries} ), 1,
        'makehosts -m keeps the IPv4 line beside the link-local line' );
}

done_testing();
