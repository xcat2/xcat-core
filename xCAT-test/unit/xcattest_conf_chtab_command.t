#!/usr/bin/env perl
# xcattest applies each row of a [Table_*] block with chtab, and runs the command through
# /bin/bash -c. A vm.othersettings value separates its settings with a semicolon:
#
#     othersettings=cpumode:host-passthrough;firmware:efi-secureboot
#
# Unquoted, bash ends the chtab command at the semicolon and runs the second setting as a
# command. These checks split the command the way the shell does and look at the words chtab
# receives.
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use Text::ParseWords qw(parse_line);

require xCAT::Test::Conf;

# The words bash gives to chtab, or undef when the command holds an unquoted shell operator.
sub chtab_words {
    my ($cmd) = @_;
    my @words = parse_line(qr/\s+/, 0, $cmd);
    return undef if grep { !defined $_ } @words;
    my @tokens = parse_line(qr/\s+/, 1, $cmd);
    return undef if grep { !/^'.*'$/s && /[;&|<>`\$()*?\[\]]/ } @tokens;
    return \@words;
}

my $cmd = xCAT::Test::Conf::chtab_command('vm', 'node', 'cn1',
    { __KEY__ => 'node', othersettings => 'cpumode:host-passthrough;firmware:efi-secureboot' });
is_deeply(
    chtab_words($cmd),
    [ 'chtab', 'node=cn1', 'vm.othersettings=cpumode:host-passthrough;firmware:efi-secureboot' ],
    'chtab receives both settings of a vm.othersettings value in one argument'
);

$cmd = xCAT::Test::Conf::chtab_command('site', 'key', 'domain name',
    { __KEY__ => 'key', value => 'a&b' });
is_deeply(
    chtab_words($cmd),
    [ 'chtab', 'key=domain name', 'site.value=a&b' ],
    'the row selector is quoted like the assignments'
);

$cmd = xCAT::Test::Conf::chtab_command('site', 'key', 'motd',
    { __KEY__ => 'key', value => "it's here" });
is_deeply(
    chtab_words($cmd),
    [ 'chtab', 'key=motd', "site.value=it's here" ],
    'a single quote in a value does not end the quoting'
);

# The values a table already held pass through unchanged.
$cmd = xCAT::Test::Conf::chtab_command('networks', 'netname', 'prov6',
    { __KEY__ => 'netname', net => '2001:db8:176::/64', mask => '/64', dynamicrange => 'a-b' });
is_deeply(
    chtab_words($cmd),
    [ 'chtab', 'netname=prov6', 'networks.dynamicrange=a-b', 'networks.mask=/64',
      'networks.net=2001:db8:176::/64' ],
    'the key column is not written as an attribute, and the assignments are sorted'
);

done_testing();
