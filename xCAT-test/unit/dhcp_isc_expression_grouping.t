#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::DHCP::BootPolicy;

# ISC dhcpd's expression grammar has no parenthesised grouping. dhcp-eval(5)
# documents exactly three boolean forms -- `not E`, `E1 and E2`, `E1 or E2` --
# and nothing that groups them, so a condition written as
#
#     if (option user-class-identifier = "xNBA" or ...) and option client-architecture = 00:00 {
#
# is rejected at the opening paren:
#
#     /etc/dhcp/dhcpd.conf line 11: left brace expected.
#
# followed by a cascade of "expecting a parameter or declaration" at every
# `} else` after it. The daemon does not start, so the whole cluster stops
# answering DHCP -- not just the branch that was mis-written.
#
# There is no way to unit test the per-node statements in dhcp.pm directly:
# they are built inline inside addnode against a live database. What can be
# checked cheaply is that no generated ISC condition anywhere in the plugin
# groups a boolean with parentheses, which is the only construct that produces
# this failure. A function call -- substring(...), suffix(...), binary-to-ascii
# -- is fine and is deliberately not matched: `option` never follows an opening
# paren in a call, only in a grouped comparison.
#
# The tokens looked for are dhcpd's, not Perl's: `exists` and `not` are left out
# because the plugin's own Perl uses them parenthesised on nearly every page,
# and a bareword `option` or `filename` immediately after `(` cannot be Perl --
# a Perl variable there would carry its sigil.

my $grouping = qr/\b(?:if|and|or)\s+\(\s*(?:option|substring|suffix|hardware|packet|filename)\b/;

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
open( my $fh, '<', $plugin ) or BAIL_OUT("cannot read $plugin: $!");
my @offenders;
while ( my $line = <$fh> ) {
    next if $line =~ /^\s*#/;
    push @offenders, "$.: $line" if $line =~ $grouping;
}
close $fh;

is_deeply( \@offenders, [],
    'no ISC condition in the dhcp plugin groups a boolean with parentheses' )
  or diag("dhcpd cannot parse these:\n@offenders");

# The same rule for the per-network architecture chain, checked against what it
# actually renders rather than against its source.
my $rendered = join '', @{ xCAT::DHCP::BootPolicy->isc_client_architecture_lines(
        next_server => '192.0.2.10',
        portsuffix  => ':8080',
        net         => '192.0.2.0',
        prefix      => 24,
    ) };

unlike( $rendered, $grouping,
    'the rendered per-network architecture chain groups nothing' );

# And the user class test itself, which is spliced into conditions that already
# carry a trailing `and option client-architecture = ...`.
foreach my $quote ( '"', '\\"' ) {
    my $test = xCAT::DHCP::BootPolicy->isc_xnba_user_class_test(quote => $quote);
    unlike( $test, qr/^\(/,
        'the xNBA user class test is a single ungrouped expression' );
}

done_testing();
