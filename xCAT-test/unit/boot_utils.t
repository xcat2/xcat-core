#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::BootUtils;

my @cases = (
    [ undef, undef, 'undefined input remains undefined' ],
    [ '', '', 'empty input remains empty' ],
    [ '0', '0', 'false string input remains unchanged' ],
    [ 'console=ttyS0 quiet', 'console=ttyS0 quiet ', 'volatile options are retained' ],
    [ 'R::root=/dev/sda R::console=ttyS0', '', 'persistent-only options are omitted' ],
    [
        'console=ttyS0 R::root=/dev/sda quiet',
        'console=ttyS0 quiet ',
        'persistent options are omitted from mixed input'
    ],
    [
        'first R::persist=1 second R::last=1 third',
        'first second third ',
        'volatile option ordering is preserved'
    ],
);

for my $case (@cases) {
    my ($input, $expected, $description) = @{$case};
    is( xCAT::BootUtils::volatile_addkcmdline($input), $expected, $description );
}

my $original = 'first R::persist=1 second';
is( xCAT::BootUtils::volatile_addkcmdline($original), 'first second ', 'the normalized value is returned' );
is( $original, 'first R::persist=1 second', 'the caller value is not modified' );

done_testing();
