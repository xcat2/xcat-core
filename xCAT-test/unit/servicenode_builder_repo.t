#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# xCAT-server requires perl modules that EL keeps in the distribution builder repository:
# perl-IO-Tty, perl-Crypt-CBC, perl-Crypt-Rijndael and perl(Expect). That repository is
# DISABLED on a fresh EL install, so dnf install xCATsn on a service node does not resolve and
# the node ends with no xcatd. The servicenode postscript enabled EPEL and nothing else.
#
# The repository has a different id on every EL vendor and release, so the decision is a sub and
# this test drives it. Enabling the repository is a side effect and stays in the postscript.

my $script = File::Spec->catfile($FindBin::Bin, '..', '..', 'xCAT', 'postscripts', 'servicenode');
plan skip_all => "servicenode not found" unless -f $script;
# The postscript guards its own body with caller(), so requiring it compiles the subs and runs
# nothing. A postscript that loses that guard executes here, which is the loud failure to have.
eval { require $script; 1 } or plan skip_all => "could not load servicenode: $@";
can_ok('main', 'builder_repo_ids') or done_testing() && exit;

sub ids { return [ main::builder_repo_ids(@_) ] }

is_deeply(ids('almalinux', '9.8', 'x86_64'), ['crb'],
    'AlmaLinux 9 names crb');
is_deeply(ids('rocky', '10.0', 'x86_64'), ['crb'],
    'Rocky 10 names crb');
is_deeply(ids('centos', '9', 'ppc64le'), ['crb'],
    'CentOS Stream 9 names crb');
is_deeply(ids('almalinux', '8.10', 'x86_64'), [ 'powertools', 'PowerTools' ],
    'AlmaLinux 8 names powertools, and the CentOS 8 spelling after it');
is_deeply(ids('rhel', '9.4', 'x86_64'), ['codeready-builder-for-rhel-9-x86_64-rpms'],
    'RHEL 9 names its arch-qualified codeready-builder repository');
is_deeply(ids('rhel', '8.9', 'ppc64le'), ['codeready-builder-for-rhel-8-ppc64le-rpms'],
    'RHEL 8 keeps the arch in the repository id');
is_deeply(ids('ol', '9.3', 'x86_64'), ['ol9_codeready_builder'],
    'Oracle Linux 9 names its own codeready builder repository');

# A caller with nothing to go on must get nothing to enable, not a guess.
is_deeply(ids(undef, '9', 'x86_64'), [], 'no distribution id yields no repository');
is_deeply(ids('almalinux', undef, 'x86_64'), [], 'no version yields no repository');
is_deeply(ids('almalinux', 'rawhide', 'x86_64'), [], 'a version with no major number yields no repository');

# The arch only reaches the RHEL id. A missing arch must not build a repository id with a hole
# in it, which dnf would accept as an unknown repository and silently skip.
is_deeply(ids('rhel', '9.4', undef), ['codeready-builder-for-rhel-9-x86_64-rpms'],
    'a missing arch falls back to x86_64 rather than an empty field');

done_testing();
