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

    sub my_ip_facing {
        my $node = shift;
        $node = shift if defined($node) && $node eq __PACKAGE__;
        return (0, '192.0.2.1');
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

done_testing();
