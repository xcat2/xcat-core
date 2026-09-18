#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use Test::More;

use xCAT::DHCP::BootPolicy;

# ISC dhcpd's expression grammar has no parenthesised grouping. dhcp-eval(5) documents
# `not E`, `E1 and E2` and `E1 or E2`, and nothing that groups them, so dhcpd rejects a
# grouped condition at the opening paren with "left brace expected" and does not start.
#
# The per-node statements in dhcp.pm are built inline against a live database, so they are
# scanned rather than driven. The two chains that can be rendered are driven below.
#
# The tokens looked for are dhcpd's, not Perl's. `exists` and `not` are left out because the
# plugin's own Perl uses them parenthesised, and a bareword `option` after `(` cannot be
# Perl, which would carry a sigil there.

my $grouping = qr/\b(?:if|and|or)\s+\(\s*(?:option|substring|suffix|hardware|packet|filename)\b/;

my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/dhcp.pm";
open( my $fh, '<', $plugin ) or die("cannot read $plugin: $!");
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
