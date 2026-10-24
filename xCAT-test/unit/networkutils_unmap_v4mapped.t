#!/usr/bin/env perl
#
# xcatd identifies a peer by reverse lookup. On a dual-stack listener an IPv4
# peer arrives as the 16-byte ::ffff:a.b.c.d, so xcatd asks for AF_INET6 and,
# when that answers nothing, retries with AF_INET. The retry passes the SAME
# 16 bytes, and gethostbyaddr with AF_INET needs 4, so the retry cannot answer.
#
# That leaves the peer unidentified whenever the mapped AF_INET6 lookup fails.
# Measured on three openEuler management nodes with the same /etc/hosts and the
# same resolver: the mapped lookup answers on glibc 2.28 and 2.38 and does not
# on glibc 2.34, where the install monitor then logged 86 times "received a
# connection request from unknown host ... The connection request will be
# ignored" and no compute node ever reached the booted state.
#
# unmap_v4mapped_addr supplies the 4-byte form the retry needs.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More tests => 5;

use xCAT::NetworkUtils;

# ::ffff:192.168.59.10 -- what a dual-stack peeraddr carries for an IPv4 peer.
my $mapped = ("\0" x 10) . "\xff\xff" . pack('C4', 192, 168, 59, 10);
is(length($mapped), 16, 'the mapped address under test is 16 bytes');

is(xCAT::NetworkUtils::unmap_v4mapped_addr($mapped), pack('C4', 192, 168, 59, 10),
    'a v4-mapped address is reduced to its 4 IPv4 bytes')
  or diag('gethostbyaddr with AF_INET cannot answer for a 16-byte address');

# The discriminator: a real IPv6 peer must keep all 16 bytes. Truncating it
# would hand gethostbyaddr the last 4 bytes of an IPv6 address as if they were
# an IPv4 address, which resolves to the wrong host or to nothing.
my $v6 = pack('n8', 0x2001, 0x0db8, 0, 0, 0, 0, 0, 1);    # 2001:db8::1
is(xCAT::NetworkUtils::unmap_v4mapped_addr($v6), $v6,
    'a genuine IPv6 address is returned unchanged');

# ::1 is 15 zero bytes and a 1, which shares no prefix with ::ffff: but is the
# nearest thing to a mapped address in the loopback case.
my $loopback6 = pack('n8', 0, 0, 0, 0, 0, 0, 0, 1);
is(xCAT::NetworkUtils::unmap_v4mapped_addr($loopback6), $loopback6,
    'the IPv6 loopback address is returned unchanged');

# A listener without IPv6 already hands over 4 bytes, and those must survive.
my $v4 = pack('C4', 10, 1, 2, 3);
is(xCAT::NetworkUtils::unmap_v4mapped_addr($v4), $v4,
    'a 4-byte IPv4 address is returned unchanged');
