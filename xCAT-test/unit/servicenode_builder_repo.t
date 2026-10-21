#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# xCAT-server requires perl modules EL keeps in the distribution builder repository:
# perl-IO-Tty, perl-Crypt-CBC, perl-Crypt-Rijndael and perl(Expect). That repository is disabled
# on a fresh EL install, so dnf install xCATsn on a service node does not resolve and the node
# ends with no xcatd. The servicenode postscript enabled EPEL and nothing else.
#
# The repository is not called crb on EL8, and each vendor names it differently, so the decision
# is a module and this is its table. Enabling the repository is a side effect and stays in the
# postscript.

use lib File::Spec->catdir($FindBin::Bin, '..', '..', 'xCAT', 'postscripts');
use_ok('ELBuilderRepo') or done_testing() && exit;

my @table = (
    # vendor      major  arch       expected ids
    [ 'almalinux', 8,  'x86_64',  [ 'powertools', 'PowerTools' ] ],
    [ 'almalinux', 9,  'x86_64',  ['crb'] ],
    [ 'almalinux', 10, 'x86_64',  ['crb'] ],
    [ 'rocky',     8,  'x86_64',  [ 'powertools', 'PowerTools' ] ],
    [ 'rocky',     9,  'ppc64le', ['crb'] ],
    [ 'rocky',     10, 'x86_64',  ['crb'] ],
    [ 'centos',    8,  'x86_64',  [ 'powertools', 'PowerTools' ] ],
    [ 'centos',    9,  'x86_64',  ['crb'] ],
    [ 'centos',    10, 'x86_64',  ['crb'] ],
    [ 'rhel',      8,  'ppc64le', ['codeready-builder-for-rhel-8-ppc64le-rpms'] ],
    [ 'rhel',      9,  'x86_64',  ['codeready-builder-for-rhel-9-x86_64-rpms'] ],
    [ 'rhel',      10, 'x86_64',  ['codeready-builder-for-rhel-10-x86_64-rpms'] ],
    [ 'ol',        8,  'x86_64',  ['ol8_codeready_builder'] ],
    [ 'ol',        9,  'x86_64',  ['ol9_codeready_builder'] ],
    [ 'ol',        10, 'x86_64',  ['ol10_codeready_builder'] ],
);

for my $row (@table) {
    my ($vendor, $major, $arch, $want) = @$row;
    my @got = ELBuilderRepo::builder_repo_ids($vendor, $major, $arch);
    is_deeply(\@got, $want, "$vendor EL$major names @$want");
}

# The EL8 name is the one that is easy to get wrong: the display name reads
# "AlmaLinux 8 - PowerTools" while the id is lowercase, and crb does not exist there at all.
for my $vendor (qw(almalinux rocky centos)) {
    my @got = ELBuilderRepo::builder_repo_ids($vendor, 8, 'x86_64');
    ok(!grep({ $_ eq 'crb' } @got), "$vendor EL8 does not name crb");
    is($got[0], 'powertools', "$vendor EL8 tries the lowercase id first");
}

# Nothing to go on must yield nothing to enable, not a guess.
is_deeply([ ELBuilderRepo::builder_repo_ids(undef, 9, 'x86_64') ], [], 'no vendor yields no repository');
is_deeply([ ELBuilderRepo::builder_repo_ids('almalinux', undef, 'x86_64') ], [], 'no major version yields no repository');
is_deeply([ ELBuilderRepo::builder_repo_ids('almalinux', '9.8', 'x86_64') ], [],
    'a version that is not a bare major yields no repository, so the caller must parse it');

# The arch reaches the RHEL id alone. A missing arch must not leave a hole in it, which dnf
# accepts as an unknown repository and skips without a word.
is_deeply([ ELBuilderRepo::builder_repo_ids('rhel', 9, undef) ],
    ['codeready-builder-for-rhel-9-x86_64-rpms'], 'a missing arch falls back to x86_64');

done_testing();
