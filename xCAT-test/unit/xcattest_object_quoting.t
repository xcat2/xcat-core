#!/usr/bin/env perl
# The chdef command xcattest builds when it applies an [Object_*] section of a conf.
#
# xcattest joined each attribute to the command unquoted and ran the result through bash. A
# conf carries values a shell reads as syntax: vmothersetting separates its settings with a
# semicolon, so "vmothersetting=cpumode:host-passthrough;firmware:efi-insecure" ended the
# chdef at the semicolon. The node kept only the first setting, the compute node was defined
# with no firmware, and it came up as a BIOS guest that cannot network boot over IPv6.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use xCAT::Test::OS;

# A value a shell would read as two commands.
is( xCAT::Test::OS::object_definition_command(
        'node', 'cn1', { vmothersetting => 'cpumode:host-passthrough;firmware:efi-insecure' } ),
    q{chdef -t node -o cn1 vmothersetting='cpumode:host-passthrough;firmware:efi-insecure'},
    'a semicolon in a value stays inside one command' );

# Several attributes keep a stable order, so the command is reproducible.
is( xCAT::Test::OS::object_definition_command(
        'node', 'cn1', { arch => 'x86_64', netboot => 'grub2' } ),
    q{chdef -t node -o cn1 arch='x86_64' netboot='grub2'},
    'every value is quoted, in attribute order' );

# The other characters a conf can carry.
is( xCAT::Test::OS::shell_quote('a b'),      q{'a b'},      'a space is quoted' );
is( xCAT::Test::OS::shell_quote('a$b'),      q{'a$b'},      'a dollar sign is quoted' );
is( xCAT::Test::OS::shell_quote('a`b`'),     q{'a`b`'},     'a backtick is quoted' );
is( xCAT::Test::OS::shell_quote(q{it's}),    q{'it'\''s'},  'a single quote is escaped' );
is( xCAT::Test::OS::shell_quote(undef),      q{''},         'an undefined value gives an empty argument' );

# What the shell actually does with the result, which is the point of the quoting.
my $cmd = xCAT::Test::OS::object_definition_command(
    'node', 'cn1', { vmothersetting => 'cpumode:host-passthrough;firmware:efi-insecure' } );
my ($value) = $cmd =~ /vmothersetting=(.*)$/;
open( my $bash, '-|', '/bin/bash', '-c', "printf %s $value" )
  or die "run bash: $!";
my $seen = do { local $/; <$bash> };
close($bash);
is( $seen, 'cpumode:host-passthrough;firmware:efi-insecure',
    'bash passes the whole value through as one argument' );

done_testing();
