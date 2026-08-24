#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::Utils;

my @cases = (
    [undef,                 'pdu',     0, 'undefined list does not match'],
    ['',                    'pdu',     0, 'empty list does not match'],
    ['pdu',                 undef,     0, 'undefined target does not match'],
    ['pdu',                 'pdu',     1, 'single value matches'],
    ['pdu,openbmc',         'openbmc', 1, 'comma-list value matches'],
    [' pdu , openbmc ',     'pdu',     1, 'leading and trailing item whitespace is ignored'],
    [' pdu , openbmc ',     'openbmc', 1, 'whitespace is ignored for later items'],
    ['0',                   '0',       1, 'defined zero matches'],
    ['not-pdu',             'pdu',     0, 'hyphenated prefix is not a match'],
    ['pdu-extra',           'pdu',     0, 'hyphenated suffix is not a match'],
    ['pdu.extra',           'pdu',     0, 'dotted suffix is not a match'],
    ['.pdu,pdu.,-pdu,pdu-', '.pdu',    1, 'leading punctuation matches exactly'],
    ['.pdu,pdu.,-pdu,pdu-', 'pdu.',    1, 'trailing punctuation matches exactly'],
    ['.pdu,pdu.,-pdu,pdu-', '-pdu',    1, 'leading hyphen matches exactly'],
    ['.pdu,pdu.,-pdu,pdu-', 'pdu-',    1, 'trailing hyphen matches exactly'],
);

foreach my $case (@cases) {
    my ($list, $value, $expected, $description) = @$case;
    is(
        xCAT::Utils->comma_list_contains($list, $value),
        $expected,
        $description,
    );
}

done_testing();
