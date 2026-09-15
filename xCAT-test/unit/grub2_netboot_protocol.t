#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(slurp_repo_file);

use Test::More;

my $grub2 = slurp_repo_file('xCAT-server/lib/xcat/plugins/grub2.pm');

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
