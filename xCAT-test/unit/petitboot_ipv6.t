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

    # The real helper brackets a placeholder that a port follows, so the port after an
    # IPv6 address can still be read, and leaves every other placeholder bare.
    sub substitute_facing_address {
        my ($cmdline, $address) = @_;
        return $cmdline unless defined($cmdline) && defined($address) && length($address);
        if (index($address, ':') >= 0) {
            $cmdline =~ s/!myipfn!(?=:\d)/[$address]/g;
        }
        $cmdline =~ s/!myipfn!/$address/g;
        return $cmdline;
    }

    sub uri_authority {
        my $address = shift;
        $address = shift if defined($address) && $address eq __PACKAGE__;
        my $port = shift;
        return unless defined($address) && length($address);
        return "[$address]:$port" if index($address, ':') >= 0;
        return "$address:$port";
    }

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

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/petitboot.pm";

# petitboot_boot_url builds the kernel and initrd URL that petitboot fetches.
is(
    xCAT_plugin::petitboot::petitboot_boot_url('http', '192.0.2.1', 80, '/tftpboot', 'xcat/osimage/vmlinuz'),
    'http://192.0.2.1:80/tftpboot/xcat/osimage/vmlinuz',
    'an IPv4 server keeps the URL byte-for-byte unchanged'
);
is(
    xCAT_plugin::petitboot::petitboot_boot_url('http', '2001:db8::1', 80, '/tftpboot', 'xcat/osimage/vmlinuz'),
    'http://[2001:db8::1]:80/tftpboot/xcat/osimage/vmlinuz',
    'an IPv6 server is bracketed so the port can still be read'
);
is(
    xCAT_plugin::petitboot::petitboot_boot_url('http', '!myipfn!', 80, '/tftpboot', 'xcat/osimage/vmlinuz'),
    'http://!myipfn!:80/tftpboot/xcat/osimage/vmlinuz',
    'the facing-address placeholder survives the URL build for the later substitution'
);
is(
    xCAT_plugin::petitboot::petitboot_boot_url('http', '2001:db8::1', 8080, '/tftpboot', 'xcat/osimage/initrd.img'),
    'http://[2001:db8::1]:8080/tftpboot/xcat/osimage/initrd.img',
    'a custom port follows the bracketed IPv6 address'
);

# petitboot_facing_address looks the facing address up in the family the node has.
@xCAT::NetworkUtils::legacy_facing_calls = ();
@xCAT::NetworkUtils::family_facing_calls = ();
is_deeply(
    [ xCAT_plugin::petitboot::petitboot_facing_address('nodev6') ],
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
    [ xCAT_plugin::petitboot::petitboot_facing_address('nodev4') ],
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
