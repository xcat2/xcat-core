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

done_testing();
