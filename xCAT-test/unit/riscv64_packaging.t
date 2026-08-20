#!/usr/bin/env perl
use strict;
use warnings;

use File::Spec;
use FindBin;
use Test::More;

# riscv64 packaging: the arch-named packages (xCAT, xCATsn) must resolve their
# architecture token and dependencies for riscv64, and the build scripts must
# know the riscv64 package names. The Genesis image comes from the OpenEmbedded
# packages, so there is no arch-named Genesis package to resolve here.

my $repo_root = File::Spec->rel2abs( File::Spec->catdir( $FindBin::Bin, '..', '..' ) );

sub read_file {
    my ($relative) = @_;
    my $path = File::Spec->catfile( $repo_root, split( m{/}, $relative ) );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my $xcat = read_file('xCAT/xCAT.spec');
like( $xcat, qr/^%ifarch riscv64\n(?:#[^\n]*\n)*Requires: ipmitool-xcat >= 1\.8\.18-4\n%endif$/m, 'xCAT.spec requires ipmitool-xcat on riscv64' );
my ($xcat_rv) = $xcat =~ /^%ifarch riscv64\n((?:#[^\n]*\n|Requires:[^\n]*\n)*)%endif$/m;
unlike( $xcat_rv || '', qr/xnba-undi|syslinux-xcat|elilo-xcat/, 'xCAT.spec does not require the x86 PXE loaders on riscv64' );

# riscv64 has no legacy Genesis package: the requirement must disappear rather than
# resolve to an unsatisfiable name, and the OpenEmbedded image is recommended instead.
like( $xcat, qr/^%\{\?genesistarch:Requires: xCAT-genesis-scripts-%\{genesistarch\} = 1:%\{version\}-%\{release\}\}$/m, 'xCAT.spec asks for the legacy Genesis package only where the architecture has one' );

SKIP: {
    skip 'rpmspec is not installed', 2 unless `sh -c 'command -v rpmspec' 2>/dev/null`;
    my $requires = `rpmspec -q --target riscv64 --requires xCAT/xCAT.spec 2>/dev/null`;
    unlike( $requires, qr/genesis-scripts/, 'a riscv64 build requires no legacy Genesis package' );
    unlike( $requires, qr/\Q%{genesistarch}\E/, 'a riscv64 build leaves no unexpanded architecture macro' );
}

my $xcatsn = read_file('xCATsn/xCATsn.spec');
like( $xcatsn, qr/^%ifarch riscv64\nRequires: ipmitool-xcat >= 1\.8\.17-1\n%endif$/m, 'xCATsn.spec requires ipmitool-xcat on riscv64' );


my $buildcore = read_file('buildcore.sh');
like( $buildcore, qr/^\s*for arch in x86_64 ppc64 ppc64le s390x aarch64 riscv64; do$/m, 'buildcore.sh builds xCAT and xCATsn for riscv64' );

my $buildlocal = read_file('buildlocal.sh');
like( $buildlocal, qr/^\s*for arch in x86_64 ppc64 s390x aarch64 riscv64; do$/m, 'buildlocal.sh builds xCAT and xCATsn for riscv64' );
like( $buildlocal, qr{^\s*cp /root/rpmbuild/RPMS/riscv64/\* \$CURDIR/build/$}m, 'buildlocal.sh collects riscv64 rpms' );

my $buildrpms = read_file('buildrpms.pl');
like( $buildrpms, qr/forcearch/, 'buildrpms.pl documents the forcearch mock configuration for riscv64 builds' );

done_testing();
