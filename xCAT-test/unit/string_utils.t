#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;

use xCAT::StringUtils qw(trim);

is( trim(undef), undef, 'undefined values remain undefined' );
is_deeply( [ trim(undef) ], [undef], 'undefined values are preserved in list context' );
is( trim(''), '', 'empty strings remain empty' );
is( trim(" \t\n"), '', 'whitespace-only strings become empty' );
is( trim('value'), 'value', 'strings without surrounding whitespace are unchanged' );
is( trim(" \tvalue\r\n"), 'value', 'leading and trailing whitespace is removed' );
is(
    trim("  first line \n second line  \n"),
    "first line \n second line",
    'whitespace inside multiline content is preserved'
);
is(
    trim("\x{2003}\x{03b1}\x{03b2}\x{2003}"),
    "\x{03b1}\x{03b2}",
    'Unicode whitespace is removed without changing non-ASCII content'
);
is( trim(0), '0', 'defined false values are preserved' );

my $original = '  original  ';
is( trim($original), 'original', 'trim returns the normalized value' );
is( $original, '  original  ', 'trim does not modify the caller value' );

done_testing();
