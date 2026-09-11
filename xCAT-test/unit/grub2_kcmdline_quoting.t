#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use Test::More;

# grub2 reads its configuration as a script. A word carrying a command separator ends the
# linux command, so the kernel never sees the rest of the line. The Ubuntu installer seed
# (ds=nocloud-net;s=<url>) is written as one such word: the node booted without the seed URL
# and without BOOTIF, and the installer waited for someone to answer its questions.

use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
my $plugin = "$FindBin::Bin/../../xCAT-server/lib/xcat/plugins/grub2.pm";
plan skip_all => 'grub2.pm not found' unless -r $plugin;
eval { require $plugin; 1 } or plan skip_all => "could not load grub2.pm: $@";

my $quote = \&xCAT_plugin::grub2::quote_kcmdline;

my $seed = 'imgurl=http://mn/rootimg.cpio.gz ds=nocloud-net;s=http://mn/install/autoinst/n1/ quiet';
is( $quote->($seed),
    'imgurl=http://mn/rootimg.cpio.gz ds=nocloud-net\;s=http://mn/install/autoinst/n1/ quiet',
    'the installer seed keeps the arguments after it' );

my $plain = 'imgurl=http://mn/rootimg.cpio.gz XCAT=10.0.0.1:3001 console=ttyS0,115200 quiet';
is( $quote->($plain), $plain, 'a command line without a separator is unchanged' );

is( $quote->(undef), undef, 'an undefined command line stays undefined' );
is( $quote->(''),    '',    'an empty command line stays empty' );

for my $char ( ';', '{', '}', '|', '&', '<', '>', '(', ')' ) {
    is( $quote->("first opt=a${char}b last"), "first opt=a\\${char}b last",
        "a separator $char is escaped" );
}

# grub2 removes the quoting before the kernel sees the value, so a value the caller quoted
# must keep the quotes it was given rather than gaining a second layer.
is( $quote->('first opt="a;b c" last'), 'first opt="a;b c" last',
    'a double quoted value is passed through unchanged' );
is( $quote->(q{first 'ds=nocloud-net;s=http://mn/seed' last}),
    q{first 'ds=nocloud-net;s=http://mn/seed' last},
    'a single quoted value is passed through unchanged' );

# A quoted span and a bare separator in the same word: the span keeps its meaning and only
# the separator outside it is escaped.
is( $quote->(q{opt='a b';c}), q{opt='a b'\;c},
    'a separator beside a quoted span is escaped without touching the span' );
is( $quote->('opt="a;b c" other=x;y'), 'opt="a;b c" other=x\;y',
    'a bare separator beside a quoted word is escaped' );

# An escaped separator is already literal to grub2, so escaping it again would hand the
# kernel a backslash the caller never wrote.
is( $quote->('first ds=nocloud-net\;s=http://mn/seed last'),
    'first ds=nocloud-net\;s=http://mn/seed last',
    'a separator the caller escaped is passed through unchanged' );
is( $quote->('a\;b c;d'), 'a\;b c\;d',
    'an escaped separator does not stop a real one being escaped' );

is( $quote->('BOOTIF=$net_default_mac x;y'), 'BOOTIF=$net_default_mac x\;y',
    'a variable reference is left alone so BOOTIF still expands' );

done_testing();
