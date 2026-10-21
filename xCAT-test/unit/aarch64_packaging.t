#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# aarch64 management node: xCAT.spec must pull the BMC tool and the iPXE loader
# (an aarch64 management node can serve x86 nodes), but not the x86-only PXE
# stack. aarch64 nodes boot through UEFI and grub2.

my $xcat = slurp_repo_file('xCAT/xCAT.spec');
my ($xcat_aa) = $xcat =~ /^%ifarch aarch64\n((?:#[^\n]*\n|Requires:[^\n]*\n)+)%endif$/m;
ok( defined $xcat_aa, 'xCAT.spec has an aarch64 Requires block' );
like( $xcat_aa || '', qr/^Requires: ipmitool-xcat >= 1\.8\.18-4$/m, 'xCAT.spec requires ipmitool-xcat on aarch64' );
like( $xcat_aa || '', qr/^Requires: ipxe-xcat >= 2\.0\.0-1$/m,      'xCAT.spec requires ipxe-xcat on aarch64 for mixed clusters' );
unlike( $xcat_aa || '', qr/xnba-undi|syslinux-xcat|elilo-xcat/, 'xCAT.spec does not require the x86 PXE loaders on aarch64' );

SKIP: {
    my $rpmspec = qx(command -v rpmspec 2>/dev/null);
    chomp($rpmspec);
    skip 'rpmspec is not installed', 2 unless $rpmspec && -x $rpmspec;

    my $spec = repo_path('xCAT/xCAT.spec');
    open( my $requires_fh, '-|',
        $rpmspec, '-q', '--target', 'aarch64', '--requires', $spec )
      or BAIL_OUT("unable to run $rpmspec: $!");
    my $requires = do { local $/; <$requires_fh> };
    close($requires_fh)
      or BAIL_OUT("rpmspec failed for $spec with status " . ($? >> 8));

    like( $requires, qr/^ipmitool-xcat >= 1\.8\.18-4$/m, 'an aarch64 build requires ipmitool-xcat' );
    unlike( $requires, qr/^(?:xnba-undi|syslinux-xcat)\b/m, 'an aarch64 build requires no x86-only PXE loader' );
}

# The EL10 aarch64 netboot files follow the other EL10 architectures: one rh
# file per kind, aliased by each rebuild distribution.
foreach my $kind (qw(pkglist exlist postinstall)) {
    my $rh = "xCAT-server/share/xcat/netboot/rh/compute.rhels10.aarch64.$kind";
    ok( -f repo_path($rh) && !-l repo_path($rh), "$rh is a regular file" );
    foreach my $distro (qw(alma rocky)) {
        my $alias = "xCAT-server/share/xcat/netboot/$distro/compute.${distro}10.aarch64.$kind";
        is( readlink( repo_path($alias) ), "../rh/compute.rhels10.aarch64.$kind", "$alias uses the EL10 file" );
    }
}

done_testing();
