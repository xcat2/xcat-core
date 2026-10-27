#!/usr/bin/env perl
#
# Kea rejects a reservation whose subnet-id arrives as a JSON string, so every Control Agent
# update falls back to a full dhcpd restart.
#
# The cause is Perl aliasing, not a type declaration: map binds $_ to the hash element itself, and
# reading a numeric subnet-id through a string function attaches a string form to that scalar.
# JSON then serialises it as "1" rather than 1. Copying the element before reading it keeps the
# value numeric.

use strict;
use warnings;
use Test::More;

BEGIN {
    eval { require JSON::XS; 1 } or plan skip_all => 'JSON::XS is required to observe the encoding';
}
plan tests => 4;

my $enc = JSON::XS->new->canonical;

# How the dedupe key is built. The second form is what the backend must use.
sub key_aliased { my ($r) = @_; join('|', map { defined($_) ? lc($_) : '' } $r->{'subnet-id'}, 'duid') }
sub key_copied  { my ($r) = @_; join('|', map { my $v = $_; defined($v) ? lc($v) : '' } $r->{'subnet-id'}, 'duid') }

my $before = { 'subnet-id' => 1 };
is($enc->encode({ 'subnet-id' => $before->{'subnet-id'} }), '{"subnet-id":1}',
    'a subnet-id straight from subnet_id_for_ip encodes as a JSON number');

my $aliased = { 'subnet-id' => 1 };
key_aliased($aliased);
is($enc->encode({ 'subnet-id' => $aliased->{'subnet-id'} }), '{"subnet-id":"1"}',
    'reading the element through an aliased $_ makes it encode as a JSON string, which Kea rejects');

my $copied = { 'subnet-id' => 1 };
key_copied($copied);
is($enc->encode({ 'subnet-id' => $copied->{'subnet-id'} }), '{"subnet-id":1}',
    'copying the element first leaves it a JSON number');

is(key_copied({ 'subnet-id' => 1 }), key_aliased({ 'subnet-id' => 1 }),
    'and both forms still build the same dedupe key, so nothing else changes');
