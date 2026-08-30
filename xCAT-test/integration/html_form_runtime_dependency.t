#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;

require_ok('HTML::Form');

my ($form) = HTML::Form->parse(
    '<form method="post"><input name="user" value="admin"></form>',
    'http://example.invalid/'
);

isa_ok($form, 'HTML::Form');
is($form->value('user'), 'admin', 'HTML form fields can be parsed');

done_testing();
