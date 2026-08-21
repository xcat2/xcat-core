#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec;
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use imgutils;

# EL riscv64 media and diskless images: the installer kernel/initrd live under
# images/pxeboot like x86 and aarch64 media, and riscv64 diskless images need
# their own default network drivers and lib64 resolver libraries. The
# behavior is pinned without running the database-backed plugins: the arch
# conditions are asserted in the shipped source and the resolver block is
# extracted and evaluated directly.

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub slurp {
    my ($relative) = @_;
    my $path = File::Spec->catfile( $repo_root, split( m{/}, $relative ) );
    plan skip_all => "$path not found" unless -r $path;
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $content = do { local $/; <$fh> };
    close($fh);
    return $content;
}

my $anaconda  = slurp('xCAT-server/lib/xcat/plugins/anaconda.pm');
my $geninitrd = slurp('xCAT-server/lib/xcat/plugins/geninitrd.pm');
my $genimage  = slurp('xCAT-server/share/xcat/netboot/rh/genimage');

# anaconda.pm: stateful install kernel/initrd discovery
like(
    $anaconda,
    qr/\( \$arch =~ \/x86\/ or \$arch =~ \/aarch64\/ or \$arch =~ \/riscv64\/ \) and\n\s*\(\n\s*-r "\$pkgdir\/images\/pxeboot\/vmlinuz"/,
    'anaconda looks for riscv64 installer kernels under images/pxeboot like x86 and aarch64',
);
like(
    $anaconda,
    qr/\/\\\/vmlinuz-\(\.\*\(x86_64\|ppc64\|el\\d\+\|ppc64le\|aarch64\|riscv64\)\)\$\//,
    'driver-disk kernel updates recognise riscv64 kernels',
);

# geninitrd.pm: diskless installer initrd source
like(
    $geninitrd,
    qr/if \(\$arch =~ \/x86\/ or \(\$arch =~ \/riscv64\/ and \$osvers !~ \/sles\|suse\/\)\) \{\n\s*if \(\$osvers =~ \/\(\^ol\[0-9\]\.\*\)\|\(centos\.\*\)\|\(alma\.\*\)\|\(rocky\.\*\)\|\(rh\.\*\)\|\(fedora\.\*\)\|\(SL\.\*\)\/\) \{\n\s*\$kernelpath = "\$tftppath\/vmlinuz";\n\s*copy\("\$pkgdir\/images\/pxeboot\/vmlinuz", \$kernelpath\);/,
    'geninitrd copies riscv64 EL kernels from images/pxeboot',
);
like(
    $geninitrd,
    qr/\$arch =~ \/riscv64\/ and \$osvers !~ \/sles\|suse\//,
    'a SUSE osimage on riscv64 keeps the unsupported-architecture error instead of reading SUSE installer media paths',
);
unlike(
    $geninitrd,
    qr/\} elsif \(\$arch =~ \/riscv64\/\)/,
    'geninitrd does not need a separate riscv64 branch',
);

is_deeply(
    [ imgutils::default_net_drivers( 'rh', 'riscv64' ) ],
    [qw/e1000 e1000e igb ixgbe r8169 tg3 bnx2x mlx5_core virtio_net/],
    'riscv64 diskless images default to virtio, Intel, Realtek, Broadcom and Mellanox drivers',
);

# rh/genimage: resolver libraries for the boot image
my ($lib_block) = $genimage =~ m{^(\s*if \(\$arch =~ /x86_64/ or \$arch =~ /aarch64/ or \$arch =~ /riscv64/\) \{\n\s*push \@filestoadd, "lib64/libnss_dns\.so\.2";\n.*?^\s*\}\n)}ms;
ok( $lib_block, 'the resolver library block was located in rh/genimage' )
  or BAIL_OUT('rh/genimage no longer matches the expected resolver library block');

sub resolver_libs {
    my ($arch) = @_;
    my $code = "sub { my \$arch = shift; my \@filestoadd;\n$lib_block\n return \@filestoadd; }";
    my $sub = eval $code;    ## no critic (BuiltinFunctions::ProhibitStringyEval)
    die "Unable to evaluate the resolver library block: $@" if $@;
    return [ $sub->($arch) ];
}

is_deeply( resolver_libs('riscv64'), [ 'lib64/libnss_dns.so.2', 'lib64/libresolv.so.2' ], 'riscv64 images take the resolver libraries from lib64' );
is_deeply( resolver_libs('x86_64'),  [ 'lib64/libnss_dns.so.2', 'lib64/libresolv.so.2' ], 'x86_64 images still use lib64' );
is_deeply( resolver_libs('ppc64'),   [ 'lib/libnss_dns.so.2',   'lib/libresolv.so.2' ],   'ppc64 images still use lib' );

# anaconda.pm: crash kernel reservation for diskless images with kdump enabled
like(
    $anaconda,
    qr/if \(\$arch eq "riscv64"\) \{\n(?:\s*#[^\n]*\n)*\s*\$kcmdline \.= " crashkernel=256M dump=\$dump ";/,
    'a riscv64 diskless image with kdump enabled reserves a crash kernel by default',
);
like(
    $anaconda,
    qr/if \(\$arch =~ \/86\/\) \{\n\s*\$kcmdline \.= " crashkernel=128M dump=\$dump ";/,
    'the x86 default reservation is unchanged',
);
like(
    $anaconda,
    qr/\$kcmdline \.= " crashkernel=\$crashkernelsize dump=\$dump ";/,
    'an explicit linuximage.crashkernelsize still wins on every architecture',
);

done_testing();
