#!/usr/bin/env perl
#
# getipaddr caches a resolved address in %::hostiphash and answers later calls
# from it. The cache bypass tests OnlyV6 and GetAllAddresses, and does not test
# OnlyV4, so a caller that asks for IPv4 can be handed a cached IPv6 address.
#
# The cache is filled by whichever lookup ran first. An unrestricted lookup
# passes AF_UNSPEC to getaddrinfo, and on a dual-stack management node with an
# AAAA record that answers with the IPv6 address, which is then stored. xcatd is
# long-lived and %::hostiphash is a global, so any earlier caller in the process
# poisons every OnlyV4 caller that follows.
#
# What it costs: debian.pm builds the Subiquity install command line with
# getipaddr($host, OnlyV4 => 1) and writes nfsroot=<address>:/install. With an
# IPv6 address that renders as nfsroot=2001:db8::1:/install, which is not a
# parseable nfsroot, so the installer never mounts and the node never installs.
# dhcp.pm and mknb.pm carry four more OnlyV4 callers with the same exposure.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::NetworkUtils;

# The address an unrestricted lookup left behind on a dual-stack host.
$::hostiphash{'mn.cluster'}{hostip} = '2001:db8::1';

my $only_v4 = xCAT::NetworkUtils->getipaddr('mn.cluster', OnlyV4 => 1);

ok(!defined($only_v4) || $only_v4 !~ /:/,
    'OnlyV4 does not return the IPv6 address an earlier lookup cached')
  or diag("getipaddr returned '$only_v4', which renders as nfsroot=$only_v4:/install");

# An IPv4 entry must still be served from the cache: the bypass is about the
# family of the cached answer, not about disabling the cache for OnlyV4.
$::hostiphash{'v4.cluster'}{hostip} = '10.1.2.3';
is(xCAT::NetworkUtils->getipaddr('v4.cluster', OnlyV4 => 1), '10.1.2.3',
    'an IPv4 cache entry is still served to an OnlyV4 caller');

# An unrestricted caller keeps its cache hit, whatever family it holds.
is(xCAT::NetworkUtils->getipaddr('mn.cluster'), '2001:db8::1',
    'a caller that did not ask for IPv4 still gets the cached address');

done_testing();
