#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

my $grub2_path = defined $ENV{XCATROOT} ? "$ENV{XCATROOT}/lib/perl/xCAT_plugin/grub2.pm" : '';
$grub2_path = "xCAT-server/lib/xcat/plugins/grub2.pm"
    unless -f $grub2_path;

plan skip_all => "grub2.pm not found" unless -f $grub2_path;

my $grub2 = do { local $/; open my $fh, '<', $grub2_path or die $!; <$fh> };

# pull the real validation pattern out of the plugin so this tests the shipped
# regex rather than a copy of it
my ($pattern) = $grub2 =~ m{unless \(\$grub2protocol =~ (/[^/]+/[a-z]*)\)};
ok($pattern, 'found the netboot protocol validation regex in grub2.pm');

my $accepts = eval "sub { my \$v = shift; return scalar(\$v =~ $pattern) }";
ok($accepts, 'validation regex compiles');

# noderes.netboot is documented as grub2, grub2-http and grub2-tftp, so the
# protocol taken from grub2-<protocol> may only ever be http or tftp
ok($accepts->('http'), 'grub2-http is accepted');
ok($accepts->('tftp'), 'grub2-tftp is accepted');

# an unanchored alternation, /^http|tftp$/, reads as (^http)|(tftp$) and lets
# these through; they then skip the httpport branch and drop the port
ok(!$accepts->('https'),  'grub2-https is rejected rather than silently dropping site.httpport');
ok(!$accepts->('httpx'),  'a protocol merely starting with http is rejected');
ok(!$accepts->('xtftp'),  'a protocol merely ending with tftp is rejected');
ok(!$accepts->('ftp'),    'an unsupported protocol is rejected');
ok(!$accepts->(''),       'an empty protocol is rejected');

done_testing();
