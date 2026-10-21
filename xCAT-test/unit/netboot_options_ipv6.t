#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";

use Test::More;
use xCAT::Utils;

is(
    xCAT::Utils->lookupNetboot('alma10.1', 'x86_64', 'Linux'),
    'xnba,pxe,grub2,grub2-tftp,grub2-http',
    'x86_64 Linux exposes GRUB TFTP and HTTP transport variants'
);

is(
    xCAT::Utils->lookupNetboot('alma10.1', 'aarch64', 'Linux'),
    'grub2',
    'other architecture choices remain unchanged'
);

done_testing();
