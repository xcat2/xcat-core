#!/usr/bin/env perl
# A [Table_*] VALUE MAY CONTAIN A COLON OR A SLASH. table_attr DROPS THE REST OF IT.
#
# xcattest applies a conf's [Table_*] blocks itself, once, before the first case runs
# (setup_env_by_configure_file), so whatever table_attr returns is what reaches chtab. Its value
# class is ([\w\.\-]+) while object_attr, beside it in the same module, already allows ":,;/" --
# so an [Object_node] ip= carries an IPv6 address and a [Table_networks] net= silently cannot.
#
# The narrow class is faithful to what it replaced: upstream xcattest still matches tables with
# ([\w\.\-]+) at line 817 and objects with ([\w\.\-\+\ \/:]+) at line 854. Moving the pair into
# xCAT::Test::Conf is what made the asymmetry visible and testable.
#
# Measured 2026-10-23 on a management node provisioning over IPv6: `net=2001:db8:176::/64` reached
# chtab as `net=2001`, and xcattest re-applied that junk row on every run. [Table_site] value= has
# the same hole, so site.master cannot be an IPv6 address either. Nothing warns: the line parses,
# the truncated value is written, and the case fails later for a reason that looks unrelated.
#
# The same hole swallows any path or time range a table value needs.
use strict;
use warnings;
use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";
use xCAT::Test::Conf ();

my $table = xCAT::Test::Conf->can('table_attr');
ok($table, 'xCAT::Test::Conf provides table_attr') or die "nothing to test\n";

# One pair per thing a table value legitimately holds. The value is what must come back WHOLE.
my @cases = (
    ['net=2001:db8:176::/64',              'net',   '2001:db8:176::/64',  'an IPv6 prefix'],
    ['    gateway=2001:db8:176::1',        'gateway', '2001:db8:176::1',  'an IPv6 address'],
    ['value=fd00::1',                      'value', 'fd00::1',            'a unique-local address'],
    ['master=192.168.201.76',              'master', '192.168.201.76',    'an IPv4 address, unchanged'],
    ['installdir=/install',                'installdir', '/install',      'an absolute path'],
    ['nameservers=2001:db8::1,2001:db8::2', 'nameservers', '2001:db8::1,2001:db8::2',
                                                                          'a comma-separated list'],
    ['domain=xcat76.lab',                  'domain', 'xcat76.lab',        'a dotted name, unchanged'],
    ['key=system',                         'key',   'system',             'a bare word, unchanged'],
);
for my $c (@cases) {
    my ($line, $attr, $value, $what) = @$c;
    my ($got_attr, $got_value) = $table->($line);
    is($got_attr,  $attr,  "$what: the attribute is $attr");
    is($got_value, $value, "$what: the value survives whole");
}

# A line with no assignment is still the empty list, and an inline comment is still excluded --
# the class holds no whitespace and no '#', so widening it does not start swallowing comments.
is_deeply([ $table->('# a comment') ], [], 'a comment line yields no assignment');
is_deeply([ $table->('[Table_site]') ], [], 'a section header yields no assignment');
my ($a, $v) = $table->('value=fd00::1   # the management address');
is($v, 'fd00::1', 'an inline comment is not part of the value');

# CONTROL: object_attr already accepts these, which is why the asymmetry is the defect rather
# than the design. Without this a reader cannot tell whether colons were meant to be refused.
my $object = xCAT::Test::Conf->can('object_attr');
ok($object, 'and object_attr, for comparison');
if ($object) {
    my (undef, $ov) = $object->('ip=2001:db8:176::20');
    is($ov, '2001:db8:176::20', 'control: an [Object_*] value already keeps an IPv6 address');
}

done_testing;
