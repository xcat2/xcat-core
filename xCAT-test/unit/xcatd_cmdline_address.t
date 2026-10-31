#!/usr/bin/env perl
#
# The xcatd= kernel argument carries the management node address and the xcatd port. An IPv6
# address holds colons, so an unbracketed "<address>:<port>" cannot be split on the colon.
# Measured on an IPv6-only node: destiny.pm wrote xcatd=2001:db8:190::1:3001, doxcat split it on
# the first colons and logged "XCATMASTER is 2001, XCATPORT is db8", then never reached xcatd and
# the node stayed out of nodelist.status.
#
# xcatd_cmdline_address brackets an IPv6 address, as RFC 3986 does, and leaves everything else
# alone. xCAT-test/bats/doxcat_xcatd_address.bats drives the reader that has to agree with it.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More tests => 8;

use xCAT::NetworkUtils;

is(xCAT::NetworkUtils::xcatd_cmdline_address('192.168.1.1', 3001), '192.168.1.1:3001',
    'an IPv4 address is unchanged, so an existing node keeps the argument it had');
is(xCAT::NetworkUtils::xcatd_cmdline_address('2001:db8:190::1', 3001), '[2001:db8:190::1]:3001',
    'an IPv6 address is bracketed, so the port can be told from the address');
is(xCAT::NetworkUtils::xcatd_cmdline_address('fe80::1', 3001), '[fe80::1]:3001',
    'a link-local address is bracketed too');
is(xCAT::NetworkUtils::xcatd_cmdline_address('::1', 3001), '[::1]:3001',
    'a loopback address is bracketed');
is(xCAT::NetworkUtils::xcatd_cmdline_address('mn.cluster', 3001), 'mn.cluster:3001',
    'a hostname carries no colon and is not bracketed');
ok(!defined(xCAT::NetworkUtils::xcatd_cmdline_address('', 3001)),
    'an empty address gives no argument rather than a bare colon');
ok(!defined(xCAT::NetworkUtils::xcatd_cmdline_address(undef, 3001)),
    'an undefined address gives no argument');

# The contract the reader depends on: bracketed address, then a colon, then the port.
like(xCAT::NetworkUtils::xcatd_cmdline_address('2001:db8:190::1', 3001),
    qr/\A\[[0-9a-f:]+\]:\d+\z/,
    'the IPv6 form is exactly what doxcat parses: [address]:port');
