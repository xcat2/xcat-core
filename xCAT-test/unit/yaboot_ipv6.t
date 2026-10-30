#!/usr/bin/env perl
use strict;
use warnings;
no warnings 'once';

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT", "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More;

BEGIN {
    package xCAT::Scope;
    $INC{'xCAT/Scope.pm'} = __FILE__;

    package xCAT::TableUtils;
    sub getTftpDir { return '/tftpboot'; }
    sub get_site_attribute { return; }
    $INC{'xCAT/TableUtils.pm'} = __FILE__;

    package xCAT::NetworkUtils;
    our %families = (nodev4 => 4, nodev6 => 6);
    our @legacy_facing_calls;
    our @family_facing_calls;

    sub node_address_family {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        return $families{$node};
    }

    sub my_ip_facing {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        push @legacy_facing_calls, $node;
        return (0, '192.0.2.1');
    }

    sub my_ip_facing_family {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        my $family = shift;
        push @family_facing_calls, [ $node, $family ];
        return (0, '2001:db8::1');
    }
    $INC{'xCAT/NetworkUtils.pm'} = __FILE__;

    package xCAT::MsgUtils;
    $INC{'xCAT/MsgUtils.pm'} = __FILE__;

    package xCAT::Table;
    sub new { return; }
    $INC{'xCAT/Table.pm'} = __FILE__;

    package xCAT::Usage;
    $INC{'xCAT/Usage.pm'} = __FILE__;

    package xCAT::InstUtils;
    sub is_me { return 0; }
    $INC{'xCAT/InstUtils.pm'} = __FILE__;
}

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/yaboot.pm";

# yaboot_config_name builds the name that yaboot asks for, from the IPv4 address.
# yaboot writes the name in lower case, unlike petitboot.
is(
    xCAT_plugin::yaboot::yaboot_config_name('192.0.2.50'),
    'c0000232',
    'an IPv4 address gives the four octets in lower-case hexadecimal'
);
is(
    xCAT_plugin::yaboot::yaboot_config_name('10.0.0.1'),
    '0a000001',
    'each octet takes two digits'
);
is(
    xCAT_plugin::yaboot::yaboot_config_name('2001:db8:156::10'),
    undef,
    'an IPv6 address has no name, rather than one that no firmware asks for'
);
is(
    xCAT_plugin::yaboot::yaboot_config_name('::1'),
    undef,
    'the IPv6 loopback has no name either'
);
is(
    xCAT_plugin::yaboot::yaboot_config_name('192.0.2.300'),
    undef,
    'an octet out of range is not an address'
);
is(
    xCAT_plugin::yaboot::yaboot_config_name(undef),
    undef,
    'an address that was not resolved has no name'
);

# yaboot_facing_address looks the facing address up in the family the node has.
@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::yaboot::yaboot_facing_address('nodev6') ],
    [ 0, '2001:db8::1' ],
    'an IPv6-only node gets the IPv6-facing address'
);
is_deeply(
    $xCAT::NetworkUtils::family_facing_calls[0],
    [ 'nodev6', 6 ],
    'an IPv6-only node is resolved through the family helper'
);
is(
    scalar(@xCAT::NetworkUtils::legacy_facing_calls),
    0,
    'an IPv6-only node does not reach the IPv4-only helper'
);

@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::yaboot::yaboot_facing_address('nodev4') ],
    [ 0, '192.0.2.1' ],
    'an IPv4 node keeps the legacy facing lookup'
);
is_deeply(
    \@xCAT::NetworkUtils::legacy_facing_calls,
    ['nodev4'],
    'an IPv4 node still reaches the legacy helper'
);
is(
    scalar(@xCAT::NetworkUtils::family_facing_calls),
    0,
    'an IPv4 node does not reach the family helper'
);

done_testing();
