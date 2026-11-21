#!/usr/bin/env perl
#
# Kea rejects a reservation whose subnet-id arrives as a JSON string, so every Control Agent
# update falls back to a full server restart.
#
# The cause is Perl aliasing: the dedupe key in live_upsert_reservations read the subnet-id of
# each reservation through an aliased $_, and reading a numeric scalar in string context attaches
# a string form to it. The reservation body is encoded from the same scalar afterwards.

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

# Only the XS backend keeps the string form that an aliased $_ attaches to the scalar. Under
# JSON::PP every assertion here passes with the bug in place, so the test skips unless the
# backend that Kea.pm will use is the XS one. The workflow installs libjson-xs-perl.
use JSON ();
BEGIN {
    plan skip_all => 'the JSON backend is ' . JSON->backend . ', which does not keep the string form'
      unless JSON->backend =~ /XS/;
}
plan tests => 6;

use xCAT::DHCP::Backend::Kea;

# Drive the real sub and encode the captured payload with the backend's own encoder, which is
# what the HTTP path uses. Asserting on the Perl value would pass with the bug in place.
sub upsert {
    my (@args) = @_;
    my @payloads;
    my $backend = xCAT::DHCP::Backend::Kea->new(
        control_agent_handler => sub {
            my ($payload) = @_;
            push @payloads, $payload;
            return { ok => 1, result => 0, response => { result => 0 } };
        },
    );
    my $result = $backend->live_upsert_reservations(@args);
    my @adds = grep { $_->{command} eq 'reservation-add' } @payloads;
    return ( $result, $backend, \@adds );
}

my $reservation = {
    'subnet-id'  => 1,
    duid         => '00:04:aa:bb',
    'ip-addresses' => ['2001:db8::20'],
    hostname     => 'node20',
};

my ( $result, $backend, $adds ) = upsert( [$reservation], service => ['dhcp6'] );
ok( !$result->{error}, 'the upsert reaches the Control Agent handler' );
is( scalar(@$adds), 1, 'one reservation-add is sent' );

my $body = $backend->encode_config( $adds->[0] );
like( $body, qr/"subnet-id"\s*:\s*1\b/,
    'the reservation body encodes subnet-id as a JSON number' );
unlike( $body, qr/"subnet-id"\s*:\s*"1"/,
    'the reservation body does not encode subnet-id as a JSON string, which Kea rejects' );

# The dedupe key is built over the stale list as well, so a stale entry reads the same scalar a
# second time.
my $stale = { 'subnet-id' => 1, duid => '00:04:cc:dd' };
( $result, $backend, $adds ) = upsert(
    [ { %$reservation } ],
    service            => ['dhcp6'],
    stale_reservations => [$stale],
);
ok( !$result->{error}, 'the upsert succeeds with a stale reservation to delete' );
like( $backend->encode_config( $adds->[0] ), qr/"subnet-id"\s*:\s*1\b/,
    'subnet-id stays a JSON number when the dedupe key also reads a stale reservation' );
