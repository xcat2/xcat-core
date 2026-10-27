#!/usr/bin/env perl
# The IPv6 boot server a grub2 node gets, and what makedhcp reports when there is none.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More tests => 12;

use xCAT::DHCP::BootPolicy;

sub choose { return xCAT::DHCP::BootPolicy->dhcp6_boot_server(@_); }

# A tftpserver that resolves over IPv6 is used as it stands.
my ($server, $warning) = choose(
    configured    => 'mn.cluster',
    configured_v6 => 'fd00::1',
    facing_v6     => 'fd00::2',
);
is($server, 'fd00::1', 'the resolved tftpserver is the boot server');
is($warning, undef, 'a resolved tftpserver raises no warning');

# A dual-stack node keeps an IPv4 tftpserver. It has no IPv6 address, so the management node
# address facing the node is used instead of failing makedhcp.
($server, $warning) = choose(
    configured    => '192.0.2.10',
    configured_v6 => undef,
    facing_v6     => 'fd00::2',
);
is($server, 'fd00::2', 'an IPv4 tftpserver falls back to the facing address');
is($warning, undef, 'the fallback raises no warning');

# <xcatmaster>, or no tftpserver at all.
($server, $warning) = choose(facing_v6 => 'fd00::2');
is($server, 'fd00::2', 'with no configured server the facing address is used');

# Nothing resolves. The caller keeps the reservation, so this is a warning and not an error.
($server, $warning) = choose(
    configured => '192.0.2.10',
    reason     => 'the xcat76-cn can not be resolved as IPv6',
);
is($server, undef, 'an unresolvable server yields no boot server');
like($warning, qr/\Q192.0.2.10\E/,
    'the warning names the configured server that did not resolve');
like($warning, qr/\Qthe xcat76-cn can not be resolved as IPv6\E/,
    'the warning carries the resolution reason');

# With no configured server there is nothing to name, so the reason stands alone.
($server, $warning) = choose(reason => 'node IPv6 address is in an undefined subnet');
is($server, undef, 'no configured server and no facing address yields none');
is($warning, 'node IPv6 address is in an undefined subnet',
    'the warning is the reason alone when no server was configured');

# my_ip_facing_family can return an empty list, which leaves no reason to report.
($server, $warning) = choose();
is($warning, 'no IPv6-facing address was found',
    'a missing reason falls back to a stated default');

# An empty tftpserver is not a configured server.
(undef, $warning) = choose(configured => '', reason => 'no route');
is($warning, 'no route', 'an empty configured server is not named in the warning');
