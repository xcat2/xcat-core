#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
BEGIN { $ENV{XCATROOT} = "$FindBin::Bin/../../xCAT-server"; }
use lib "$FindBin::Bin/../../xCAT-server/lib";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../perl-xCAT";

use Socket ();
use Test::More;

$ENV{XCATCFG} ||= 'SQLite:/tmp';

my $source_hosts_plugin =
  "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/hosts.pm";
if (-f $source_hosts_plugin) {
    require $source_hosts_plugin;
} else {
    require xCAT_plugin::hosts;
}

ok(
    xCAT_plugin::hosts::_host_entry_matches(
        '192.0.2.10 node01 node01.example.com',
        'node01',
        '192.0.2.10'
    ),
    'host-entry matching preserves IPv4 behavior'
);
ok(
    !xCAT_plugin::hosts::_host_entry_matches('', 'node01', '192.0.2.10'),
    'blank host entry does not match'
);
ok(
    xCAT_plugin::hosts::_host_entry_matches(
        '010.1.1.1 node01 node01.example.com',
        'node01',
        '192.0.2.10'
    ),
    'legacy numeric-quad entries remain replaceable and deletable by node'
);

my $has_core_ipv6_parser = defined(&Socket::inet_pton)
  && eval { defined(Socket::inet_pton(Socket::AF_INET6(), '::1')) };
my $has_ipv6_parser = $has_core_ipv6_parser
  || eval { require Socket6; 1 };

SKIP: {
    skip 'No IPv6 literal parser is available', 8 unless $has_ipv6_parser;

    ok(
        xCAT_plugin::hosts::_host_entry_matches(
            '2001:db8::10 node01 node01.example.com',
            'node01',
            '2001:db8::10'
        ),
        'IPv6 host entry matches its address and node'
    );
    ok(
        xCAT_plugin::hosts::_host_entry_matches(
            '2001:0db8:0000:0000:0000:0000:0000:0010 old-name',
            'node01',
            '2001:db8::10'
        ),
        'equivalent expanded and compressed IPv6 addresses are deduplicated'
    );
    ok(
        xCAT_plugin::hosts::_host_entry_matches(
            '2001:db8::20 node01.example.com node01',
            'node01',
            '2001:db8::10'
        ),
        'same-node IPv6 entry matches after an address change'
    );
    ok(
        !xCAT_plugin::hosts::_host_entry_matches(
            '2001:db8::20 node010 node010.example.com',
            'node01',
            '2001:db8::10'
        ),
        'similarly prefixed IPv6 node does not match'
    );
    ok(
        !xCAT_plugin::hosts::_host_entry_matches(
            '2001:db8::20 node010 node01',
            'node01',
            '2001:db8::10'
        ),
        'an alias alone does not identify a host entry for replacement'
    );
    ok(
        !xCAT_plugin::hosts::_host_entry_matches(
            'not-an-address node01 node01.example.com',
            'node01',
            '2001:db8::10'
        ),
        'a hostname-like first field is not treated as a host address'
    );

    my @addnode_args;
    {
        no warnings qw(once redefine);
        local *xCAT_plugin::hosts::getIPdomain = sub {
            return ('example.com', 'v6net');
        };
        local *xCAT_plugin::hosts::addnode = sub {
            @addnode_args = @_;
            return;
        };
        xCAT_plugin::hosts::addotherinterfaces(
            undef,
            'node01',
            'node01-v6!2001:db8::10',
            'example.com'
        );
    }
    is(
        $addnode_args[1],
        'node01-v6',
        'otherinterfaces parses an IPv6 interface hostname with !'
    );
    is(
        $addnode_args[2],
        '2001:db8::10',
        'otherinterfaces passes the IPv6 literal to addnode'
    );
}

# makehosts reads the entry test in four places, and an address it rejects
# reaches no host entry at all. addotherinterfaces is covered above; the three
# blocks below drive the remaining places with an IPv6 address and read the
# host entries each one produced. _set_host_lines answers the live host-entry
# array, so the later calls are read through that reference.
{
    no warnings qw(once redefine);

    my @messages;
    my $collect = sub { push @messages, $_[0]; return; };
    local *xCAT_plugin::hosts::getIPdomain = sub { return ( 'example.com', 'v6net' ); };

    my %table_rows;
    local *xCAT::Table::new = sub {
        my ( $class, $name ) = @_;
        return bless { name => $name }, 'xCAT::Table';
    };
    local *xCAT::Table::getNodesAttribs = sub { return \%table_rows; };

    # add_hosts_content - makehosts with a noderange.
    %table_rows = ( node01 => [ { node => 'node01', ip => '2001:db8::10' } ] );
    @messages = ();
    xCAT_plugin::hosts::_set_host_lines( [] );
    my @written;
    xCAT_plugin::hosts::add_hosts_content(
        nodelist => ['node01'],
        callback => $collect,
        delnode  => 0,
        domain   => 'example.com',
        hostsref => \@written
    );
    is_deeply(
        [ grep { /\S/ } @written ],
        ["2001:db8::10 node01 node01.example.com \n"],
        'add_hosts_content writes a host entry for an IPv6 node address'
    );
    is( scalar(@messages), 0,
        'add_hosts_content reports no warning for an IPv6 node address' );

    %table_rows = ( node01 => [ { node => 'node01', ip => 'not-an-address' } ] );
    @messages = ();
    xCAT_plugin::hosts::_set_host_lines( [] );
    my @rejected;
    xCAT_plugin::hosts::add_hosts_content(
        nodelist => ['node01'],
        callback => $collect,
        delnode  => 0,
        domain   => 'example.com',
        hostsref => \@rejected
    );
    is_deeply( [ grep { /\S/ } @rejected ],
        [], 'add_hosts_content writes no host entry for an address it rejects' );
    ok( scalar(@messages), 'add_hosts_content reports the address it rejects' );

    # delotherinterfaces - makehosts -d on a node with IPv6 otherinterfaces.
    my $entries = xCAT_plugin::hosts::_set_host_lines(
        [   "2001:db8::10 node01 node01.example.com \n",
            "2001:db8::20 node01-v6 node01-v6.example.com \n",
        ]
    );
    xCAT_plugin::hosts::delotherinterfaces( 'node01', 'node01-v6!2001:db8::20',
        'example.com' );
    is_deeply(
        [ grep { /\S/ } @{$entries} ],
        ["2001:db8::10 node01 node01.example.com \n"],
        'delotherinterfaces removes the entry of an IPv6 otherinterfaces address'
    );

    # add_all_hosts_content - makehosts with no noderange.
    @messages = ();
    $entries  = xCAT_plugin::hosts::_set_host_lines( [] );
    my @allnodes = xCAT_plugin::hosts::add_all_hosts_content(
        hostents => [
            { node => 'node01', ip => '2001:db8::10' },
            { node => 'node02', ip => '192.0.2.10' },
        ],
        callback => $collect,
        domain   => 'example.com'
    );
    is_deeply( \@allnodes, [ 'node01', 'node02' ],
        'add_all_hosts_content answers every node of the hosts table' );
    is_deeply(
        [ grep { /\S/ } @{$entries} ],
        [   "2001:db8::10 node01 node01.example.com \n",
            "192.0.2.10 node02 node02.example.com \n",
        ],
        'add_all_hosts_content writes a host entry for an IPv6 and an IPv4 address'
    );
    is( scalar(@messages), 0,
        'add_all_hosts_content reports no error for an IPv6 address' );
}

done_testing();
