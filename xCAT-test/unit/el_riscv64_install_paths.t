#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
use lib "$FindBin::Bin/../../xCAT-server/share/xcat/netboot/imgutils";
use imgutils;

use XCAT::Test::File qw(repo_path slurp_repo_file);

# EL riscv64 media and diskless images: the installer kernel/initrd live under
# images/pxeboot like x86 and aarch64 media, and riscv64 diskless images need
# their own default network drivers and lib64 resolver libraries. The
# behavior is pinned without running the database-backed plugins: the arch
# conditions are asserted in the shipped source and the resolver block is
# extracted and evaluated directly.

my @source_files = (
    'xCAT-server/lib/xcat/plugins/anaconda.pm',
    'xCAT-server/lib/xcat/plugins/geninitrd.pm',
    'xCAT-server/share/xcat/netboot/rh/genimage',
);
foreach my $relative (@source_files) {
    my $path = repo_path($relative);
    plan skip_all => "$path not found" unless -r $path;
}

my $anaconda  = slurp_repo_file($source_files[0]);
my $geninitrd = slurp_repo_file($source_files[1]);
my $genimage  = slurp_repo_file($source_files[2]);

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
    qr/if \(\$arch =~ \/x86\/ or \(\$arch =~ \/riscv64\/ and \$osvers !~ \/sles\|suse\/\)\) \{/,
    'geninitrd routes riscv64 EL media through the installer pxeboot path',
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
# anaconda.pm: crash kernel reservation for diskless images with kdump enabled
like(
    $anaconda,
    qr/if \(\$arch eq "riscv64"\) \{\n(?:\s*#[^\n]*\n)*\s*\$kcmdline \.= " crashkernel=256M dump=\$dump ";/,
    'a riscv64 diskless image with kdump enabled reserves a crash kernel by default',
);
done_testing();
