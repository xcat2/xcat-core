#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use FindBin;
use lib "$FindBin::Bin/../lib";
use Test::More;

use XCAT::Test::File qw(slurp_repo_file);

# Fragments specify requested kernel options; they do not prove the built kernel configuration.
my $yocto_release_key =
  slurp_repo_file('xCAT-genesis-base/oe/keys/yocto-release.asc');
is( sha256_hex($yocto_release_key),
    '42d49e59f2aa01a1c1417a52d3c915a24a64060c852f33e3bd04fbb738457e70',
    'vendored Yocto release key matches the reviewed key material' );

my $ppc64_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-ppc64.cfg'
);
like( $ppc64_kernel_config, qr/^CONFIG_CPU_BIG_ENDIAN=y$/m,
    'ppc64 fragment requests big endian' );
like( $ppc64_kernel_config, qr/^# CONFIG_CPU_LITTLE_ENDIAN is not set$/m,
    'ppc64 fragment disables little endian' );

my $kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86-common.cfg'
);
for my $symbol (
    qw(
      CONFIG_MODULES CONFIG_MEGARAID_SAS CONFIG_SCSI_MPT3SAS CONFIG_SCSI_HPSA
      CONFIG_BLK_DEV_NVME CONFIG_IXGBE CONFIG_I40E CONFIG_ICE CONFIG_MLX5_CORE
      CONFIG_INFINIBAND CONFIG_MLX5_INFINIBAND CONFIG_IPMI_HANDLER CONFIG_EDAC
      CONFIG_USB_STORAGE CONFIG_BLK_DEV_LOOP CONFIG_OVERLAY_FS CONFIG_SQUASHFS
      CONFIG_SQUASHFS_XATTR CONFIG_SQUASHFS_ZSTD
    )
  )
{
    like( $kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "x86_64 fragment requests $symbol" );
}

my $x86_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86.cfg'
);
like( $x86_kernel_config, qr/^CONFIG_M686=y$/m,
    'x86 fragment selects the i686 processor family' );
like( $x86_kernel_config, qr/^# CONFIG_M586 is not set$/m,
    'x86 fragment disables i586' );
like( $x86_kernel_config, qr/^CONFIG_HIGHMEM4G=y$/m,
    'x86 fragment requests the 32-bit high-memory model' );
like( $x86_kernel_config, qr/^# CONFIG_X86_MCE is not set$/m,
    'x86 fragment disables machine-check registers' );
for my $vendor (qw(AMD INTEL)) {
    like( $x86_kernel_config,
        qr/^# CONFIG_X86_MCE_\Q$vendor\E is not set$/m,
        "x86 fragment disables the $vendor machine-check feature" );
}

my $x86_64_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86-64.cfg'
);
like( $x86_64_kernel_config, qr/^CONFIG_EDAC_AMD64=m$/m,
    'x86_64 keeps its architecture-specific EDAC driver' );

my $armv7hf_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-armv7hf.cfg'
);
for my $symbol (
    qw(
      CONFIG_ARCH_VIRT CONFIG_AEABI CONFIG_VFP CONFIG_SERIAL_AMBA_PL011
      CONFIG_VIRTIO_MMIO CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET
      CONFIG_SCSI_MPT3SAS CONFIG_MEGARAID_SAS CONFIG_BLK_DEV_NVME
      CONFIG_IXGBE CONFIG_MLX4_CORE CONFIG_INFINIBAND CONFIG_IPMI_HANDLER
      CONFIG_USB_XHCI_HCD CONFIG_USB_STORAGE CONFIG_BLK_DEV_LOOP
      CONFIG_OVERLAY_FS CONFIG_SQUASHFS
    )
  )
{
    like( $armv7hf_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "armv7hf fragment requests $symbol" );
}

my $aarch64_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-aarch64.cfg'
);
for my $symbol (
    qw(
      CONFIG_ARM64 CONFIG_ARCH_VIRT CONFIG_SERIAL_AMBA_PL011
      CONFIG_VIRTIO_PCI CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET
      CONFIG_SCSI_MPT3SAS CONFIG_SCSI_HPSA CONFIG_MEGARAID_SAS
      CONFIG_BLK_DEV_NVME CONFIG_IXGBE CONFIG_I40E CONFIG_ICE
      CONFIG_MLX5_CORE CONFIG_INFINIBAND CONFIG_MLX5_INFINIBAND
      CONFIG_IPMI_HANDLER CONFIG_EDAC CONFIG_USB_XHCI_HCD
      CONFIG_USB_STORAGE CONFIG_BLK_DEV_LOOP CONFIG_OVERLAY_FS CONFIG_SQUASHFS
    )
  )
{
    like( $aarch64_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "aarch64 fragment requests $symbol" );
}

my $riscv64_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-riscv64.cfg'
);
for my $symbol (
    qw(
      CONFIG_64BIT CONFIG_RISCV CONFIG_RISCV_SBI CONFIG_SERIAL_8250_CONSOLE
      CONFIG_VIRTIO_PCI CONFIG_VIRTIO_BLK CONFIG_VIRTIO_NET
      CONFIG_SCSI_MPT3SAS CONFIG_SCSI_HPSA CONFIG_MEGARAID_SAS
      CONFIG_BLK_DEV_NVME CONFIG_IXGBE CONFIG_I40E CONFIG_ICE
      CONFIG_MLX5_CORE CONFIG_INFINIBAND CONFIG_MLX5_INFINIBAND
      CONFIG_IPMI_HANDLER CONFIG_EDAC CONFIG_USB_XHCI_HCD
      CONFIG_USB_STORAGE CONFIG_BLK_DEV_LOOP CONFIG_OVERLAY_FS CONFIG_SQUASHFS
    )
  )
{
    like( $riscv64_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "riscv64 fragment requests $symbol" );
}

for my $symbol (
    qw(
      CONFIG_ACPI CONFIG_ACPI_APEI CONFIG_ACPI_APEI_GHES
      CONFIG_EFI CONFIG_EFI_STUB
    )
  )
{
    like( $riscv64_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "riscv64 fragment requests $symbol to boot on ACPI firmware" );
}

my $powerpc64_kernel_config = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-powerpc64.cfg'
);
for my $symbol (
    qw(
      CONFIG_PPC_PSERIES CONFIG_PPC_POWERNV CONFIG_PPC_64S_HASH_MMU
      CONFIG_PPC_RADIX_MMU CONFIG_SCSI_IPR CONFIG_SCSI_IBMVSCSI
      CONFIG_SCSI_IBMVFC CONFIG_MEGARAID_SAS CONFIG_BLK_DEV_NVME
      CONFIG_IBMVETH CONFIG_IBMVNIC CONFIG_MLX5_CORE CONFIG_INFINIBAND
      CONFIG_IPMI_HANDLER CONFIG_USB_XHCI_HCD CONFIG_USB_STORAGE
      CONFIG_BLK_DEV_LOOP CONFIG_OVERLAY_FS CONFIG_SQUASHFS
    )
  )
{
    like( $powerpc64_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "64-bit Power fragment requests $symbol" );
}
like( $powerpc64_kernel_config, qr/^# CONFIG_PPC_VAS is not set$/m,
    'POWER8 fragment disables VAS facilities' );

my $console_service = slurp_repo_file(
    'xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console@.service'
);
like( $console_service, qr/^Environment=TERM=xterm$/m,
    'console service sets the terminal type' );
like( $console_service, qr/^Environment=COLUMNS=80$/m,
    'status console fixes the serial width' );
like( $console_service, qr/^Environment=LINES=24$/m,
    'status console fixes the serial height' );
like( $console_service, qr/^TTYPath=\/dev\/%I$/m,
    'status console binds to the machine console' );
unlike( $console_service, qr/xcat\.debug-shell|genesis-debug-shell/,
    'status console has no boot-time debug escape' );


done_testing();
