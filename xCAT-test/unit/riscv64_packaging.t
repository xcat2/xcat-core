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


my $buildcore = slurp_repo_file('buildcore.sh');
like( $buildcore, qr/^\s*for arch in x86_64 ppc64 ppc64le s390x aarch64 riscv64; do$/m, 'buildcore.sh builds xCAT and xCATsn for riscv64' );

my $buildlocal = slurp_repo_file('buildlocal.sh');
like( $buildlocal, qr/^\s*for arch in x86_64 ppc64 s390x aarch64 riscv64; do$/m, 'buildlocal.sh builds xCAT and xCATsn for riscv64' );
like( $buildlocal, qr{^\s*cp /root/rpmbuild/RPMS/riscv64/\* \$CURDIR/build/$}m, 'buildlocal.sh collects riscv64 rpms' );

my $buildrpms = slurp_repo_file('buildrpms.pl');
like( $buildrpms, qr/forcearch/, 'buildrpms.pl documents the forcearch mock configuration for riscv64 builds' );
unlike(
    $buildrpms,
    qr/^use XCAT::BuildUtils\b/m,
    'the dependency bootstrap does not treat the repository build utility as an RPM dependency'
);
like(
    $buildrpms,
    qr{require "\$Bin/build-utils/lib/XCAT/BuildUtils\.pm";},
    'buildrpms loads the repository build utility by path at runtime'
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
