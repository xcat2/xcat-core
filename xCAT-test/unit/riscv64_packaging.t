#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::Test::File qw(repo_path);
use XCAT::BuildUtils qw(targetarch_from_target);

my $architectures = repo_path('build-utils/rpm-architectures.sh');
is(system('sh', '-n', $architectures), 0, 'the shared build architecture data parses as POSIX shell');
open(
    my $arch_fh,
    '-|',
    'sh', '-c',
    '. "$1"; printf "%s\n%s\n%s\n" "$XCAT_CORE_RPM_ARCHES" "$XCAT_LOCAL_RPM_ARCHES" "$XCAT_LOCAL_COLLECT_ARCHES"',
    'sh', $architectures,
) or BAIL_OUT("unable to load $architectures: $!");
my @architecture_sets = <$arch_fh>;
close($arch_fh) or BAIL_OUT("unable to read architecture data from $architectures");
chomp @architecture_sets;

is(
    $architecture_sets[0],
    'x86_64 ppc64 ppc64le s390x aarch64 riscv64',
    'the release build includes riscv64 without changing its existing architecture set',
);
is(
    $architecture_sets[1],
    'x86_64 ppc64 s390x aarch64 riscv64',
    'the local build includes riscv64 without changing its existing architecture set',
);
is(
    $architecture_sets[2],
    'noarch x86_64 ppc64 riscv64',
    'the local build collects the riscv64 packages it produces',
);

# buildrpms.pl derives the rpm architecture from the mock target name through
# the loadable build utility, so exercise the implementation directly.
is( targetarch_from_target('rocky-10-riscv64-xcat', 'x86_64'), 'riscv64', 'a suffixed riscv64 forcearch target resolves to riscv64' );
is( targetarch_from_target('rocky-10-riscv64',      'x86_64'), 'riscv64', 'the stock riscv64 target resolves to riscv64' );
is( targetarch_from_target('alma+epel-10-ppc64le',  'x86_64'), 'ppc64le', 'the ppc64le target still resolves to ppc64le' );
is( targetarch_from_target('alma+epel-10-x86_64',   'x86_64'), 'x86_64',  'the x86_64 target still resolves to x86_64' );
is( targetarch_from_target('opensuse-leap-15.6-x86_64', 'x86_64'), 'x86_64', 'a dashed distro name still resolves its arch' );
is( targetarch_from_target('custom-target-foo', 'x86_64'), 'foo', 'a target without an architecture token keeps the last part' );
is( targetarch_from_target(undef, 'x86_64'), 'x86_64', 'no target means the host architecture' );

done_testing();
