#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use lib "$FindBin::Bin/../../build-utils/lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);
use XCAT::BuildUtils qw(targetarch_from_target);

# riscv64 packaging: the arch-named packages (xCAT, xCATsn) must resolve their
# architecture token and dependencies for riscv64, and the build scripts must
# know the riscv64 package names. The Genesis image comes from the OpenEmbedded
# packages, so there is no arch-named Genesis package to resolve here.

my $xcat = slurp_repo_file('xCAT/xCAT.spec');
like( $xcat, qr/^%ifarch riscv64\n(?:#[^\n]*\n)*Requires: ipmitool-xcat >= 1\.8\.18-4\n%endif$/m, 'xCAT.spec requires ipmitool-xcat on riscv64' );
my ($xcat_rv) = $xcat =~ /^%ifarch riscv64\n((?:#[^\n]*\n|Requires:[^\n]*\n)*)%endif$/m;
unlike( $xcat_rv || '', qr/xnba-undi|syslinux-xcat|elilo-xcat/, 'xCAT.spec does not require the x86 PXE loaders on riscv64' );

# riscv64 has no legacy Genesis package: the requirement must disappear rather than
# resolve to an unsatisfiable name, and the OpenEmbedded image is recommended instead.
like( $xcat, qr/^%\{\?genesistarch:Requires: xCAT-genesis-scripts-%\{genesistarch\} = 1:%\{version\}-%\{release\}\}$/m, 'xCAT.spec asks for the legacy Genesis package only where the architecture has one' );

SKIP: {
    my $rpmspec = qx(command -v rpmspec 2>/dev/null);
    chomp($rpmspec);
    skip 'rpmspec is not installed', 2 unless $rpmspec && -x $rpmspec;

    my $spec = repo_path('xCAT/xCAT.spec');
    open( my $requires_fh, '-|',
        $rpmspec, '-q', '--target', 'riscv64', '--requires', $spec )
      or BAIL_OUT("unable to run $rpmspec: $!");
    my $requires = do { local $/; <$requires_fh> };
    close($requires_fh)
      or BAIL_OUT("rpmspec failed for $spec with status " . ($? >> 8));

    unlike( $requires, qr/genesis-scripts/, 'a riscv64 build requires no legacy Genesis package' );
    unlike( $requires, qr/\Q%{genesistarch}\E/, 'a riscv64 build leaves no unexpanded architecture macro' );
}

my $xcatsn = slurp_repo_file('xCATsn/xCATsn.spec');
like( $xcatsn, qr/^%ifarch riscv64\nRequires: ipmitool-xcat >= 1\.8\.17-1\n%endif$/m, 'xCATsn.spec requires ipmitool-xcat on riscv64' );

my $server = slurp_repo_file('xCAT-server/xCAT-server.spec');
like( $server, qr/^Recommends: perl-DB_File$/m, 'xCAT-server.spec recommends perl-DB_File on EL10 (riscv64 has no EPEL to provide it)' );
like(
    $server,
    qr/^%if 0%\{\?rhel\} >= 10\nRecommends: perl-DB_File\n/m,
    'the weak perl-DB_File dependency is limited to EL10, where riscv64 has no EPEL',
);
like(
    $server,
    qr/^%else\nRequires: perl-DB_File\n%endif$/m,
    'build hosts without weak dependencies keep the hard perl-DB_File requirement',
);
like(
    $server,
    qr/^%global __requires_exclude %\{\?__requires_exclude:%\{__requires_exclude\}\|\}\^perl\\\\\(DB_File\\\\\)\$$/m,
    'xCAT-server.spec appends the generated perl(DB_File) requirement to the build root filter',
);
like( $server, qr/^Requires: perl-Net-Telnet perl-Net-DNS perl-Crypt-CBC perl-Crypt-Rijndael$/m, 'xCAT-server.spec keeps the other EL perl requires' );


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
