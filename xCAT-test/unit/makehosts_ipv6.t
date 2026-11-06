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

# addnode and delnode are the paths makehosts takes for every host entry, and
# they find an existing entry through the host-entry index. Each block below
# runs them and reads the host entries that came out. _set_host_lines answers
# the live array, so a later call is read through that reference.
#
# The index keys on a canonical address, so one host never gets a second entry
# because its address is spelled another way.
no warnings qw(once redefine);
local *xCAT_plugin::hosts::getIPdomain = sub { return ( 'example.com', 'v6net' ); };

# entries_after <lines> <operation> -- seed the host entries, run one
# operation, and answer the entries that are left.
sub entries_after {
    my ( $lines, $operation ) = @_;
    my $entries = xCAT_plugin::hosts::_set_host_lines($lines);
    $operation->();
    return [ grep { /\S/ } @{$entries} ];
}

sub add {
    my ( $node, $ip ) = @_;
    return sub {
        xCAT_plugin::hosts::addnode( undef, $node, $ip, '', 'example.com' );
    };
}

sub del {
    my ( $node, $ip ) = @_;
    return sub {
        xCAT_plugin::hosts::delnode( $node, $ip, '', 'example.com' );
    };
}

is_deeply(
    entries_after( [], add( 'node01', '2001:db8::10' ) ),
    ["2001:db8::10 node01 node01.example.com \n"],
    'addnode writes a host entry for an IPv6 address'
);

is_deeply(
    entries_after(
        ["2001:db8::10 node01 node01.example.com \n"],
        add( 'node01', '2001:db8::20' )
    ),
    ["2001:db8::20 node01 node01.example.com \n"],
    'an IPv6 address change leaves one host entry, not two'
);

is_deeply(
    entries_after(
        ["192.0.2.10 node01 node01.example.com \n"],
        add( 'node01', '192.0.2.20' )
    ),
    ["192.0.2.20 node01 node01.example.com \n"],
    'an IPv4 address change still leaves one host entry'
);

is_deeply(
    entries_after(
        ["2001:0db8:0000:0000:0000:0000:0000:0010 old-name old-name.example.com \n"],
        add( 'node01', '2001:db8::10' )
    ),
    ["2001:db8::10 node01 node01.example.com \n"],
    'an expanded IPv6 entry is replaced by the compressed spelling of it'
);

is_deeply(
    entries_after(
        ["2001:db8::10 node01 node01.example.com \n"],
        add( 'node01', '2001:0db8:0000:0000:0000:0000:0000:0010' )
    ),
    ["2001:0db8:0000:0000:0000:0000:0000:0010 node01 node01.example.com \n"],
    'a compressed IPv6 entry is replaced by the expanded spelling of it'
);

is_deeply(
    entries_after(
        ["2001:db8::10 node01 node01.example.com \n"],
        del( 'node01', '2001:0db8:0000:0000:0000:0000:0000:0010' )
    ),
    [],
    'delnode removes an entry whose address is spelled another way'
);

# A different node name takes the node index out of the answer, so the match
# comes from the address key alone.
is_deeply(
    entries_after(
        ["2001:db8::10 node01 node01.example.com \n"],
        add( 'node02', '2001:0db8:0000:0000:0000:0000:0000:0010' )
    ),
    ["2001:0db8:0000:0000:0000:0000:0000:0010 node02 node02.example.com \n"],
    'an address already in use is one entry, whichever way each side spells it'
);

is_deeply(
    entries_after(
        ["2001:db8::10 node01 node01.example.com \n"],
        del( 'node01', '2001:db8::10' )
    ),
    [],
    'delnode removes an IPv6 entry'
);

is_deeply(
    entries_after(
        [   "2001:db8::10 node01 node01.example.com \n",
            "2001:db8::11 node010 node010.example.com \n",
        ],
        add( 'node01', '2001:db8::20' )
    ),
    [   "2001:db8::20 node01 node01.example.com \n",
        "2001:db8::11 node010 node010.example.com \n",
    ],
    'a node whose name is a prefix of another keeps its own entry'
);

is_deeply(
    entries_after(
        ["2001:db8::10 node01.example.com node01 \n"],
        add( 'node01', '2001:db8::20' )
    ),
    ["2001:db8::20 node01 node01.example.com \n"],
    'an entry whose first name is the FQDN is found by the short node name'
);

is_deeply(
    entries_after(
        ["010.1.1.1 node01 node01.example.com \n"],
        add( 'node01', '192.0.2.10' )
    ),
    ["192.0.2.10 node01 node01.example.com \n"],
    'a legacy numeric-quad entry is still replaceable by node name'
);

# A host with no IPv6 parser cannot canonicalise, so the index keys on the
# literal. An address change written the same way still leaves one entry.
# An equivalent spelling becomes a second entry, which is all such a host can
# do.
{
    local *Socket::inet_pton = sub { return; };
    is_deeply(
        entries_after(
            ["2001:db8::10 node01 node01.example.com \n"],
            add( 'node01', '2001:db8::20' )
        ),
        ["2001:db8::20 node01 node01.example.com \n"],
        'without an IPv6 parser an address change still leaves one entry'
    );
    is_deeply(
        entries_after(
            ["2001:db8::10 node01 node01.example.com \n"],
            add( 'node02', '2001:0db8:0000:0000:0000:0000:0000:0010' )
        ),
        [   "2001:db8::10 node01 node01.example.com \n",
            "2001:0db8:0000:0000:0000:0000:0000:0010 node02 node02.example.com \n",
        ],
        'without an IPv6 parser an equivalent spelling becomes a second entry'
    );
}

# makehosts reads the entry test in four places, and an address it rejects
# reaches no host entry at all. addotherinterfaces is covered above; the three
# blocks below drive the remaining places with an IPv6 address and read the
# host entries each one produced. _set_host_lines answers the live host-entry
# array, so the later calls are read through that reference.
{
    my @messages;
    my $collect = sub { push @messages, $_[0]; return; };

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
