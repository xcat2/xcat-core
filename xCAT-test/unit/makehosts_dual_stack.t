#!/usr/bin/env perl
#
# A dual-stack node has an A line and an AAAA line in /etc/hosts under one node name, and that is
# the only way to give it both records through makehosts and makedns. The node index recorded node
# names for IPv6 lines as well as IPv4 ones, and addnode overwrites the first match and blanks every
# other one, so running makehosts for a node with an IPv4 hosts.ip deleted its IPv6 line.
#
# A node name now matches only lines of the family being written. The reason the index records node
# names at all -- so a node that CHANGES address does not leave a second entry -- still holds, and
# is asserted here per family.

use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use Test::More tests => 13;

require "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/hosts.pm";
my $pkg = 'xCAT_plugin::hosts';
no strict 'refs';
my $set   = \&{"${pkg}::_set_host_lines"};
my $match = \&{"${pkg}::_matching_host_indexes"};
use strict 'refs';

# A dual-stack node: both families under one name.
$set->([ "192.0.2.10 node01\n", "2001:db8::10 node01\n" ]);

my @v4 = $match->('node01', '192.0.2.10');
is(scalar(@v4), 1, 'writing the IPv4 address matches one line');
is($v4[0], 0, 'and it is the IPv4 line, so the IPv6 line is not blanked');

my @v6 = $match->('node01', '2001:db8::10');
is(scalar(@v6), 1, 'writing the IPv6 address matches one line');
is($v6[0], 1, 'and it is the IPv6 line, so the IPv4 line is not blanked');

# The reason the node index exists: a node that changes address must not leave a second entry.
$set->([ "192.0.2.10 node01\n", "2001:db8::10 node01\n" ]);
my @moved4 = $match->('node01', '192.0.2.99');
is(scalar(@moved4), 1, 'an IPv4 address change still matches the old IPv4 line');
is($moved4[0], 0, 'so makehosts replaces it instead of adding a second entry');

my @moved6 = $match->('node01', '2001:db8::99');
is(scalar(@moved6), 1, 'an IPv6 address change still matches the old IPv6 line');
is($moved6[0], 1, 'so the IPv6 entry is replaced, not duplicated');

# A name that is not in the file matches nothing, so the matcher is not simply permissive.
is(scalar($match->('node99', '192.0.2.99')), 0, 'an unknown node matches no line');

# A DELETE takes every family. The filter above keeps the other record during an update; applied
# to a delete it left the old record behind when the address of a node changed family, and
# makedhcp then wrote a DHCPv4 reservation for a node whose only address was IPv6.
no strict 'refs';
my $del = \&{"${pkg}::delnode"};
use strict 'refs';

$set->([ "192.0.2.10 node01\n", "2001:db8::10 node01\n", "192.0.2.11 node02\n" ]);
is(scalar($match->('node01', '2001:db8::10', all_families => 1)), 2,
    'a delete matches the lines of both families');

# The address of the node changed from IPv4 to IPv6, and then the node is deleted. _set_host_line
# maintains the index, so a line that no longer matches is a line that was removed.
$del->('node01', '2001:db8::10');
is(scalar($match->('node01', '192.0.2.10')), 0, 'the IPv4 record of the deleted node is gone');
is(scalar($match->('node01', '2001:db8::10')), 0, 'the IPv6 record of the deleted node is gone');
is(scalar($match->('node02', '192.0.2.11')), 1, 'and the other node still has its line');
