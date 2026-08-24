#!/usr/bin/env perl
use strict;
use warnings;

use Digest::SHA qw(sha256_hex);
use File::Spec;
use FindBin;
use Test::More;

my $repo_root = File::Spec->catdir( $FindBin::Bin, '..', '..' );

sub read_file {
    my ($relative_path) = @_;
    my $path = File::Spec->catfile( $repo_root, split( '/', $relative_path ) );
    open( my $fh, '<', $path ) or die "Unable to read $path: $!";
    my $contents = do { local $/; <$fh> };
    close($fh);
    return $contents;
}

my $kas = read_file('xCAT-genesis-builder/oe/kas/common.yml');
like( $kas, qr/tag: yocto-6\.0\.2/, 'build uses Yocto 6.0.2' );
like( $kas, qr/fingerprint: 2AFB13F28FBBB0D1B9DAF63087EB3D32FB631AD9/,
    'build trusts the Yocto release key' );
like( $kas,
    qr{yocto-release:.*?repo: xcat-core.*?path: xCAT-genesis-builder/oe/keys/yocto-release\.asc}s,
    'build loads the Yocto release key from the source tree' );
like( $kas,
    qr{xcat-core:.*?layers:.*?xCAT-genesis-builder/oe/meta-xcat-genesis:}s,
    'build loads the Genesis layer from the source tree' );
unlike( $kas, qr/gpg_keyserver:/,
    'build does not depend on a public keyserver' );
like( $kas, qr/INHERIT \+= "archiver create-spdx vex"/,
    'build generates source archives, an SBOM, and VEX metadata' );
like( $kas, qr/ARCHIVER_MODE\[src\] = "original"/,
    'release archives retain original sources' );
like( $kas, qr/ARCHIVER_MODE\[diff\] = "1"/,
    'release archives retain applied changes' );
like( $kas, qr/ARCHIVER_MODE\[recipe\] = "1"/,
    'release archives retain recipe metadata' );

my $yocto_release_key =
  read_file('xCAT-genesis-builder/oe/keys/yocto-release.asc');
is( sha256_hex($yocto_release_key),
    '42d49e59f2aa01a1c1417a52d3c915a24a64060c852f33e3bd04fbb738457e70',
    'vendored Yocto release key matches the reviewed key material' );
like( $kas,
    qr{bitbake:.*?commit: acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd.*?signed: true}s,
    'BitBake revision requires a signed tag' );
like( $kas,
    qr{openembedded-core:.*?commit: 5d1aa5c806c061a2994f4decb59016610f093213.*?signed: true}s,
    'OpenEmbedded-Core revision requires a signed tag' );
like( $kas,
    qr{meta-openembedded:.*?commit: af8b6d6b2f0b11595b0a0d5b82efa3129d52a628}s,
    'meta-openembedded revision is pinned' );

my $x86_kas = read_file('xCAT-genesis-builder/oe/kas/x86_64.yml');
like( $x86_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'x86_64 build includes the common configuration' );
like( $x86_kas, qr/^machine: xcat-genesis-x86-64$/m,
    'x86_64 build selects its machine' );

my $x86_32_kas = read_file('xCAT-genesis-builder/oe/kas/x86.yml');
like( $x86_32_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'x86 build includes the common configuration' );
like( $x86_32_kas, qr/^machine: xcat-genesis-x86$/m,
    'x86 build selects its machine' );

my $armv7hf_kas = read_file('xCAT-genesis-builder/oe/kas/armv7hf.yml');
like( $armv7hf_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'armv7hf build includes the common configuration' );
like( $armv7hf_kas, qr/^machine: xcat-genesis-armv7hf$/m,
    'armv7hf build selects its machine' );

my $aarch64_kas = read_file('xCAT-genesis-builder/oe/kas/aarch64.yml');
like( $aarch64_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'aarch64 build includes the common configuration' );
like( $aarch64_kas, qr/^machine: xcat-genesis-aarch64$/m,
    'aarch64 build selects its machine' );

my $riscv64_kas = read_file('xCAT-genesis-builder/oe/kas/riscv64.yml');
like( $riscv64_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'riscv64 build includes the common configuration' );
like( $riscv64_kas, qr/^machine: xcat-genesis-riscv64$/m,
    'riscv64 build selects its machine' );

my $ppc64le_kas = read_file('xCAT-genesis-builder/oe/kas/ppc64le.yml');
like( $ppc64le_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'ppc64le build includes the common configuration' );
like( $ppc64le_kas, qr/^machine: xcat-genesis-ppc64le$/m,
    'ppc64le build selects its machine' );

my $ppc64_kas = read_file('xCAT-genesis-builder/oe/kas/ppc64.yml');
like( $ppc64_kas, qr{includes:\s*\n\s*- xCAT-genesis-builder/oe/kas/common\.yml},
    'ppc64 build includes the common configuration' );
like( $ppc64_kas, qr/^machine: xcat-genesis-ppc64$/m,
    'ppc64 build selects its machine' );

my $build = read_file('xCAT-genesis-builder/oe/build');
like( $build, qr/aarch64\|armv7hf\|riscv64\|x86\|x86_64\|ppc64\|ppc64le/,
    'build accepts each supported architecture' );
like( $build, qr{kas/\$architecture\.yml},
    'build selects the architecture configuration directly' );

my $distro = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/distro/xcat-genesis.conf'
);
like( $distro, qr/^DISTRO_CODENAME = "cheetah"$/m,
    'distro uses the Cheetah codename' );
like( $distro, qr/^LINUX_VERSION_EXTENSION = "-xCAT-genesis"$/m,
    'kernel release identifies xCAT Genesis' );
like( $distro,
    qr/^KERNEL_MODULE_PACKAGE_SUFFIX = "-\$\{KERNEL_VERSION_PKG_NAME\}"$/m,
    'kernel module package names use the normalized kernel release' );
like( $distro, qr/^TCLIBC = "glibc"$/m, 'distro uses glibc' );
like( $distro, qr/^INIT_MANAGER = "systemd"$/m,
    'distro uses systemd' );
like( $distro, qr/^DISTRO_FEATURES_DEFAULTS = ""$/m,
    'distro disables inherited feature defaults' );
like( $distro,
    qr/^DISTRO_FEATURES = "acl ipv4 ipv6 largefile pci seccomp"$/m,
    'distro keeps an explicit feature list' );
like( $distro, qr/^NO_RECOMMENDATIONS = "1"$/m,
    'image excludes package recommendations' );
like( $distro, qr/PACKAGECONFIG:pn-systemd = ".*\bsysext\b.*"/,
    'systemd includes system extensions' );
like( $distro,
    qr/^PACKAGECONFIG:pn-networkmanager = "crypto-null libedit man-resolv-conf nmcli systemd"$/m,
    'NetworkManager keeps the minimal feature set' );
like( $distro, qr/^PACKAGECONFIG:append:pn-iproute2 = " rdma"$/m,
    'iproute2 includes the RDMA command' );
like( $distro, qr/^NETWORKMANAGER_DHCP_DEFAULT:pn-networkmanager = "internal"$/m,
    'NetworkManager uses its internal DHCP client' );
like( $distro,
    qr/^NETWORKMANAGER_DNS_RC_MANAGER_DEFAULT:pn-networkmanager = "symlink"$/m,
    'NetworkManager manages the resolver symlink' );
unlike( $distro, qr/\b(?:dhclient|dhcpcd)\b/,
    'distro excludes external DHCP clients' );

my $machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-x86-64.conf'
);
like( $machine, qr/^DEFAULTTUNE = "x86-64"$/m,
    'x86_64 uses the baseline tune' );
unlike( $machine, qr/x86-64-v[234]/,
    'x86_64 does not require a newer ISA level' );
like( $machine, qr/^MACHINE_FEATURES_DEFAULTS = ""$/m,
    'machine disables inherited feature defaults' );
like( $machine, qr/^MACHINE_FEATURES = "pci"$/m,
    'machine keeps an explicit feature list' );
like( $machine, qr/^IMAGE_FSTYPES = "cpio\.gz ext4"$/m,
    'machine builds netboot and VM filesystems' );
like( $machine, qr/^QB_DEFAULT_FSTYPE = "ext4"$/m,
    'QEMU uses a generated filesystem type' );
like( $machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "ttyS0"$/m,
    'x86_64 status console uses its serial terminal' );
like( $machine, qr/^XCAT_GENESIS_ARCHITECTURE = "x86_64"$/m,
    'x86_64 exports its canonical extension identity' );

my $ppc64le_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-ppc64le.conf'
);
like( $ppc64le_machine, qr/^DEFAULTTUNE = "ppc64p8le"$/m,
    'ppc64le uses the POWER8 little-endian tune' );
like( $ppc64le_machine, qr/^KERNEL_IMAGETYPE = "vmlinux"$/m,
    'ppc64le builds a directly bootable kernel' );
like( $ppc64le_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "hvc0"$/m,
    'ppc64le status console uses its hypervisor terminal' );
like( $ppc64le_machine, qr/^QB_MACHINE = "-machine pseries"$/m,
    'ppc64le QEMU target uses pSeries' );
like( $ppc64le_machine, qr/^QB_CPU = "-cpu POWER8"$/m,
    'ppc64le QEMU target uses the supported CPU baseline' );
unlike( $ppc64le_machine, qr/^DEFAULTTUNE = "ppc64"$/m,
    'ppc64le is not aliased to big-endian ppc64' );
like( $ppc64le_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "ppc64le"$/m,
    'ppc64le exports its canonical extension identity' );

my $ppc64_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-ppc64.conf'
);
like( $ppc64_machine, qr/^DEFAULTTUNE = "powerpc64"$/m,
    'ppc64 uses the generic big-endian ABI' );
unlike( $ppc64_machine, qr/^DEFAULTTUNE = "ppc64p8le"$/m,
    'ppc64 is not aliased to little-endian ppc64le' );
like( $ppc64_machine, qr/^QB_MACHINE = "-machine pseries"$/m,
    'ppc64 QEMU target uses pSeries' );
like( $ppc64_machine, qr/^QB_CPU = "-cpu POWER8"$/m,
    'ppc64 QEMU target can emulate the generic ABI' );
like( $ppc64_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "hvc0"$/m,
    'ppc64 status console uses its hypervisor terminal' );
like( $ppc64_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "ppc64"$/m,
    'ppc64 exports its canonical extension identity' );

my $x86_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-x86.conf'
);
like( $x86_machine, qr/^DEFAULTTUNE = "i686"$/m,
    'x86 uses the i686 baseline' );
unlike( $x86_machine, qr/^DEFAULTTUNE = "i586"$/m,
    'x86 does not retain the i586 baseline' );
like( $x86_machine, qr/^QB_SYSTEM_NAME = "qemu-system-i386"$/m,
    'x86 uses the 32-bit QEMU system target' );
like( $x86_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "ttyS0"$/m,
    'x86 status console uses its serial terminal' );
like( $x86_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "x86"$/m,
    'x86 exports its canonical extension identity' );

my $armv7hf_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-armv7hf.conf'
);
like( $armv7hf_machine, qr/^DEFAULTTUNE = "armv7ahf"$/m,
    'armv7hf uses the ARMv7-A hard-float tune' );
like( $armv7hf_machine, qr/^ARM_INSTRUCTION_SET = "arm"$/m,
    'armv7hf does not require Thumb instructions' );
unlike( $armv7hf_machine, qr/neon/i,
    'armv7hf does not require NEON' );
like( $armv7hf_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "armv7hf"$/m,
    'armv7hf exports its canonical extension identity' );
like( $armv7hf_machine, qr/^QB_MACHINE = "-machine virt,highmem=off"$/m,
    'armv7hf QEMU target uses the virtual platform' );
like( $armv7hf_machine, qr/^QB_CPU = "-cpu cortex-a15"$/m,
    'armv7hf QEMU target uses an ARMv7 CPU' );
like( $armv7hf_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "ttyAMA0"$/m,
    'armv7hf status console uses its PL011 terminal' );

my $aarch64_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-aarch64.conf'
);
like( $aarch64_machine, qr/^DEFAULTTUNE = "aarch64"$/m,
    'aarch64 uses the generic ARMv8-A tune' );
like( $aarch64_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "aarch64"$/m,
    'aarch64 exports its canonical extension identity' );
like( $aarch64_machine, qr/^QB_MACHINE = "-machine virt"$/m,
    'aarch64 QEMU target uses the virtual platform' );
like( $aarch64_machine, qr/^QB_CPU = "-cpu cortex-a57"$/m,
    'aarch64 QEMU target uses its conservative CPU baseline' );
like( $aarch64_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "ttyAMA0"$/m,
    'aarch64 status console uses its PL011 terminal' );

my $riscv64_machine = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/conf/machine/xcat-genesis-riscv64.conf'
);
like( $riscv64_machine, qr/^DEFAULTTUNE = "riscv64"$/m,
    'riscv64 uses the RV64GC tune' );
like( $riscv64_machine, qr/^XCAT_GENESIS_ARCHITECTURE = "riscv64"$/m,
    'riscv64 exports its canonical extension identity' );
like( $riscv64_machine, qr/^EXTRA_IMAGEDEPENDS = "opensbi"$/m,
    'riscv64 builds its OpenSBI firmware' );
like( $riscv64_machine, qr/^QB_DEFAULT_BIOS = "fw_jump\.elf"$/m,
    'riscv64 QEMU target boots the built OpenSBI firmware' );
like( $riscv64_machine, qr/^QB_MACHINE = "-machine virt"$/m,
    'riscv64 QEMU target uses the virtual platform' );
like( $riscv64_machine, qr/^QB_CPU = "-cpu rv64"$/m,
    'riscv64 QEMU target uses the generic CPU' );
like( $riscv64_machine, qr/^XCAT_GENESIS_CONSOLE_TTY = "ttyS0"$/m,
    'riscv64 status console uses its 8250 terminal' );

for my $machine_console (
    [ x86_64  => $machine ],
    [ x86     => $x86_machine ],
    [ ppc64   => $ppc64_machine ],
    [ ppc64le => $ppc64le_machine ],
    [ armv7hf => $armv7hf_machine ],
    [ aarch64 => $aarch64_machine ],
    [ riscv64 => $riscv64_machine ],
  )
{
    unlike( $machine_console->[1],
        qr/^QB_KERNEL_CMDLINE_APPEND = ".*xcat\.debug-shell/m,
        "$machine_console->[0] VM starts the status console" );
}

my $image = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/images/xcat-genesis-image.bb'
);
unlike( $image,
    qr/\b(?:dhclient|dhcpcd|busybox-udhcpc|systemd-networkd)\b/,
    'base image excludes alternate network clients' );
like( $image, qr/\bxcat-genesis-network\b/,
    'base image includes the Genesis network policy' );
like( $image, qr/\bxcat-genesis-protocol\b/,
    'base image includes the destiny clients' );
like( $image, qr/\bpackagegroup-xcat-genesis-hardware\b/,
    'base image includes open hardware tools' );
like( $image, qr/\bxcat-genesis-extensions\b/,
    'base image includes the signed extension loader' );
like( $image, qr/\bxcat-genesis-console\b/,
    'base image includes the status console' );

my $hardware_group = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/packagegroups/packagegroup-xcat-genesis-hardware.bb'
);
for my $tool (
    qw(
      pciutils usbutils hwloc ethtool rdma-core iproute2-rdma lldpd ipmitool curl jq
      nvme-cli smartmontools sg3-utils lsscsi mdadm hdparm parted lvm2
      memtester stress-ng edac-utils kernel-modules mstflint
      xcat-genesis-hardware-control
    )
  )
{
    like( $hardware_group, qr/\b\Q$tool\E\b/,
        "hardware group includes $tool" );
}
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-x86-64 = " dmidecode lshw mcelog"$/m,
    'x86_64 diagnostics are architecture scoped' );
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-x86 = " dmidecode lshw"$/m,
    'x86 omits the unsupported machine-check daemon' );
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-armv7hf = " dmidecode lshw"$/m,
    'armv7hf diagnostics are architecture scoped' );
unlike( $hardware_group, qr/xcat-genesis-armv7(?:\s|\b)/,
    'hardware packages do not use the old ARMv7 name' );
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-ppc64 = " dmidecode xcat-genesis-hardware-control-iprutils"$/m,
    'ppc64 includes the Power RAID provider' );
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-ppc64le = " dmidecode xcat-genesis-hardware-control-iprutils"$/m,
    'ppc64le includes the Power RAID provider' );
like( $hardware_group,
    qr/^RDEPENDS:\$\{PN\}:append:xcat-genesis-riscv64 = " lshw"$/m,
    'RISC-V omits unsupported DMI tools' );
unlike( $hardware_group,
    qr/\b(?:storcli|perccli|ssacli|arcconf|nvidia-smi|rocm-smi)\b/i,
    'base image excludes vendor-only tools' );

my $hardware_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-hardware-control/xcat-genesis-hardware-control_1.0.bb'
);
like( $hardware_recipe,
    qr/^RDEPENDS:\$\{PN\} = "bash coreutils jq mstflint nvme-cli util-linux-flock"$/m,
    'hardware control dependencies are explicit' );
like( $hardware_recipe,
    qr/^PACKAGES:prepend:xcat-genesis-ppc64 = "\$\{PN\}-iprutils "$/m,
    'iprutils provider package supports ppc64' );
like( $hardware_recipe,
    qr/^PACKAGES:prepend:xcat-genesis-ppc64le = "\$\{PN\}-iprutils "$/m,
    'iprutils provider package supports ppc64le' );
like( $hardware_recipe,
    qr/^RDEPENDS:\$\{PN\}-iprutils:xcat-genesis-ppc64 = "\$\{PN\} bash iprutils"$/m,
    'ppc64 iprutils dependencies are architecture scoped' );
like( $hardware_recipe,
    qr/^RDEPENDS:\$\{PN\}-iprutils:xcat-genesis-ppc64le = "\$\{PN\} bash iprutils"$/m,
    'iprutils provider dependencies are architecture scoped' );
like( $hardware_recipe, qr/\$\{datadir\}\/xcat\/genesis\/providers/,
    'provider manifests use an architecture-neutral data path' );
unlike( $hardware_recipe,
    qr/\b(?:storcli|perccli|ssacli|arcconf|nvidia-smi|rocm-smi)\b/i,
    'hardware control excludes vendor-only tools' );

my $hardware_dispatcher = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-hardware-control/files/genesis-hardware'
);
like( $hardware_dispatcher,
    qr/destructive capability requires a task identity/,
    'destructive operations require a task identity' );
like( $hardware_dispatcher,
    qr/destructive capability requires an exact device identity/,
    'destructive operations require an exact device' );
like( $hardware_dispatcher, qr/write_audit started/,
    'destructive operations start an audit record' );
like( $hardware_dispatcher, qr/write_audit completed/,
    'successful destructive operations complete their audit record' );
like( $hardware_dispatcher, qr/write_audit failed/,
    'failed destructive operations close their audit record' );

for my $provider (qw(nvme mstflint iprutils)) {
    my $manifest = read_file(
        "xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-hardware-control/files/$provider.json"
    );
    unlike( $manifest, qr/"destructive"\s*:\s*true/,
        "$provider base provider is read-only" );
}

my $mstflint = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-support/mstflint/mstflint_4.36.0.bb'
);
like( $mstflint,
    qr/^LICENSE = "Linux-OpenIB & MIT & BSD-2-Clause"$/m,
    'mstflint records every linked source license' );
like( $mstflint,
    qr/^SRCREV = "b9d9e844a14ae1c85cb90c76ccd4a56a0eccd599"$/m,
    'mstflint source revision is pinned' );
like( $mstflint, qr/^RDEPENDS:\$\{PN\} = "python3-modules"$/m,
    'mstflint installs its Python runtime' );
like( $mstflint, qr/^PACKAGECONFIG \?\?= "adb cables dc inband openssl"$/m,
    'mstflint omits the non-portable rdmem tool' );
unlike( $mstflint, qr/--enable-(?:fw-mgr|nvml)/,
    'mstflint excludes vendor-coupled features' );

my $iprutils = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-support/iprutils/iprutils_2.4.19.bb'
);
like( $iprutils, qr/^LICENSE = "CPL-1\.0"$/m,
    'iprutils records its source license' );
like( $iprutils,
    qr/^SRCREV = "9961e538736a6e81f1072a926c3ad91b8513c8c1"$/m,
    'iprutils source revision is pinned' );
like( $iprutils, qr/^COMPATIBLE_HOST = "powerpc64\.\*-linux"$/m,
    'iprutils is restricted to 64-bit Power targets' );
like( $iprutils, qr/--without-systemd --without-initscripts/,
    'iprutils omits unused background services' );

my $kernel_append = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto_%.bbappend'
);
like( $kernel_append, qr/file:\/\/xcat-genesis-x86-64\.cfg/,
    'x86_64 kernel uses the Genesis hardware fragment' );
like( $kernel_append, qr/file:\/\/xcat-genesis-x86-common\.cfg/,
    'x86 targets share their hardware fragment' );
like( $kernel_append, qr/file:\/\/xcat-genesis-x86\.cfg/,
    'x86 kernel uses its baseline fragment' );
like( $kernel_append, qr/do_kernel_metadata:prepend:xcat-genesis-x86/,
    'x86 replaces the upstream QEMU CPU policy' );
like( $kernel_append, qr/file:\/\/xcat-genesis-armv7hf\.cfg/,
    'armv7hf kernel uses the Genesis hardware fragment' );
like( $kernel_append,
    qr/^SRCREV_machine:xcat-genesis-armv7hf = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"$/m,
    'armv7hf kernel revision is pinned' );
like( $kernel_append, qr/file:\/\/xcat-genesis-aarch64\.cfg/,
    'aarch64 kernel uses the Genesis hardware fragment' );
like( $kernel_append,
    qr/^SRCREV_machine:xcat-genesis-aarch64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"$/m,
    'aarch64 kernel revision is pinned' );
like( $kernel_append, qr/file:\/\/xcat-genesis-riscv64\.cfg/,
    'riscv64 kernel uses the Genesis hardware fragment' );
like( $kernel_append,
    qr/^SRCREV_machine:xcat-genesis-riscv64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"$/m,
    'riscv64 kernel revision is pinned' );
like( $kernel_append, qr/file:\/\/xcat-genesis-powerpc64\.cfg/,
    '64-bit Power kernels share the Genesis hardware fragment' );
like( $kernel_append,
    qr/^SRCREV_machine:xcat-genesis-ppc64le = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"$/m,
    'ppc64le kernel revision is pinned' );
like( $kernel_append, qr/do_kernel_metadata:prepend:xcat-genesis-ppc64le/,
    'ppc64le repairs the upstream kernel metadata before configuration' );
like( $kernel_append,
    qr/^SRCREV_machine:xcat-genesis-ppc64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"$/m,
    'ppc64 kernel revision is pinned' );
like( $kernel_append, qr/do_kernel_metadata:prepend:xcat-genesis-ppc64\(\)/,
    'ppc64 repairs the upstream kernel metadata before configuration' );
like( $kernel_append, qr/file:\/\/xcat-genesis-ppc64\.cfg/,
    'ppc64 kernel uses its big-endian fragment' );

my $ppc64_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-ppc64.cfg'
);
like( $ppc64_kernel_config, qr/^CONFIG_CPU_BIG_ENDIAN=y$/m,
    'ppc64 kernel is big endian' );
like( $ppc64_kernel_config, qr/^# CONFIG_CPU_LITTLE_ENDIAN is not set$/m,
    'ppc64 kernel is not little endian' );

my $kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86-common.cfg'
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
        "x86_64 kernel enables $symbol" );
}

my $x86_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86.cfg'
);
like( $x86_kernel_config, qr/^CONFIG_M686=y$/m,
    'x86 kernel selects the i686 processor family' );
like( $x86_kernel_config, qr/^# CONFIG_M586 is not set$/m,
    'x86 kernel does not retain i586' );
like( $x86_kernel_config, qr/^CONFIG_HIGHMEM4G=y$/m,
    'x86 kernel supports the 32-bit high-memory model' );
like( $x86_kernel_config, qr/^# CONFIG_X86_MCE is not set$/m,
    'x86 kernel supports processors without machine-check registers' );
for my $vendor (qw(AMD INTEL)) {
    like( $x86_kernel_config,
        qr/^# CONFIG_X86_MCE_\Q$vendor\E is not set$/m,
        "x86 kernel disables the $vendor machine-check feature" );
}

my $x86_64_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-x86-64.cfg'
);
like( $x86_64_kernel_config, qr/^CONFIG_EDAC_AMD64=m$/m,
    'x86_64 keeps its architecture-specific EDAC driver' );

my $armv7hf_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-armv7hf.cfg'
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
        "armv7hf kernel enables $symbol" );
}

my $aarch64_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-aarch64.cfg'
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
        "aarch64 kernel enables $symbol" );
}

my $riscv64_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-riscv64.cfg'
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
        "riscv64 kernel enables $symbol" );
}

for my $symbol (
    qw(
      CONFIG_ACPI CONFIG_ACPI_APEI CONFIG_ACPI_APEI_GHES
      CONFIG_EFI CONFIG_EFI_STUB
    )
  )
{
    like( $riscv64_kernel_config, qr/^\Q$symbol\E=[ym]$/m,
        "riscv64 kernel enables $symbol to boot on ACPI firmware" );
}

my $powerpc64_kernel_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-kernel/linux/linux-yocto/xcat-genesis-powerpc64.cfg'
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
        "64-bit Power kernel enables $symbol" );
}
like( $powerpc64_kernel_config, qr/^# CONFIG_PPC_VAS is not set$/m,
    'POWER8 image disables unsupported VAS facilities' );

my $protocol_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-xcat/xcat-genesis-protocol/xcat-genesis-protocol_1.0.bb'
);
like( $protocol_recipe,
    qr{^FILESEXTRAPATHS:prepend := "\$\{THISDIR\}/\.\./\.\./\.\./\.\./\.\./xCAT-genesis-scripts/usr/bin:"$}m,
    'destiny clients use the canonical scripts' );
like( $protocol_recipe, qr/file:\/\/getdestiny.*file:\/\/nextdestiny/s,
    'both destiny clients are packaged' );
like( $protocol_recipe, qr/^RDEPENDS:\$\{PN\} = "bash openssl-bin"$/m,
    'destiny client dependencies are explicit' );
unlike( $protocol_recipe, qr/\bdoxcat\b/,
    'obsolete bootstrap script is excluded' );

my $networkmanager = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-connectivity/networkmanager/networkmanager_%.bbappend'
);
like( $networkmanager, qr/^EXTRA_OEMESON:append = " -Dtests=no"$/m,
    'NetworkManager omits its test suite' );
like( $networkmanager,
    qr{sed -i '/\^Also=NetworkManager-wait-online\.service\$/d'},
    'NetworkManager does not enable wait-online' );

my $network_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-network/xcat-genesis-network_1.0.bb'
);
like( $network_recipe,
    qr/^RDEPENDS:\$\{PN\} = "networkmanager-daemon networkmanager-nmcli"$/m,
    'network policy installs the daemon and nmcli' );

my $network_config = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-connectivity/xcat-genesis-network/files/10-xcat-genesis.conf'
);
like( $network_config, qr/^ipv4\.dhcp-timeout=20$/m,
    'IPv4 DHCP has a bounded timeout' );
like( $network_config, qr/^ipv6\.dhcp-duid=ll$/m,
    'IPv6 DHCP uses the link-layer DUID' );
like( $network_config, qr/^ipv6\.dhcp-timeout=20$/m,
    'IPv6 DHCP has a bounded timeout' );

my $init_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/xcat-genesis-init_1.0.bb'
);
like( $init_recipe, qr/\bcoreutils\b/,
    'runtime status dependencies are explicit' );
like( $init_recipe, qr/\butil-linux-logger\b/,
    'runtime logging dependency is explicit' );
like( $init_recipe, qr/file:\/\/genesis-status/,
    'runtime status helper is packaged' );
like( $init_recipe, qr/file:\/\/genesis-maintenance-shell/,
    'maintenance shell is packaged' );
like( $init_recipe, qr/file:\/\/genesis-functions/,
    'shared runtime functions are packaged' );
like( $init_recipe,
    qr/install -m 0644 .*genesis-functions.*\$\{libexecdir\}\/xcat\/genesis-functions/s,
    'shared runtime functions are installed as data' );
unlike( $init_recipe, qr/genesis-debug-shell|XCAT_GENESIS_DEBUG/,
    'legacy debug shell is absent from the image recipe' );

my $legacy_debug_shell = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files genesis-debug-shell)
);
my $legacy_debug_service = File::Spec->catfile(
    $repo_root,
    qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-init files xcat-genesis-debug-shell@.service)
);
ok( !-e $legacy_debug_shell, 'legacy debug shell script is removed' );
ok( !-e $legacy_debug_service, 'legacy debug shell service is removed' );

my $maintenance_shell = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/genesis-maintenance-shell'
);
like( $maintenance_shell, qr/^#!\/bin\/bash$/m,
    'maintenance shell uses the packaged Bash runtime' );
like( $maintenance_shell, qr/^printf 'xCAT Genesis maintenance shell\\n'$/m,
    'maintenance shell identifies Genesis' );
like( $maintenance_shell, qr/^printf 'Exit returns to the status console\.\\n\\n'$/m,
    'maintenance shell explains how to return to the console' );
like( $maintenance_shell, qr/^export PS1='genesis# '$/m,
    'maintenance shell has an explicit prompt' );
like( $maintenance_shell, qr{^exec /bin/bash --noprofile --norc -i$}m,
    'maintenance shell starts isolated Bash' );

my $status_helper = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/genesis-status'
);
like( $status_helper, qr/mktemp .*\.\$\{component\}\.XXXXXX/,
    'runtime status records use atomic temporary files' );
like( $status_helper, qr/tr -cd '\\040-\\176'/,
    'runtime status details are printable text' );

my $console_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/xcat-genesis-console_1.0.bb'
);
like( $console_recipe, qr/^DEPENDS = "libnewt systemd"$/m,
    'status console builds against libnewt and the journal API' );
like( $console_recipe,
    qr/^RDEPENDS:\$\{PN\} = "libnewt libsystemd ncurses-terminfo-base xcat-genesis-init"$/m,
    'status console installs its terminal and maintenance-shell runtime' );
like( $console_recipe, qr/^inherit meson pkgconfig systemd$/m,
    'status console uses the project build definition' );
unlike( $console_recipe, qr/\b(?:whiptail|popt)\b/,
    'status console omits the dialog wrapper' );

my $console_build = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console/meson.build'
);
like( $console_build, qr/'c_std=c17'/,
    'status console uses the C17 language contract' );
like( $console_build, qr/dependency\('libnewt'\).*dependency\('libsystemd'\)/s,
    'status console links Newt and the journal client library' );
like( $console_build, qr/'werror=true'/,
    'status console treats compiler warnings as build failures' );

my $console_service = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console@.service'
);
like( $console_service, qr/^Environment=TERM=xterm$/m,
    'status console redraws line graphics after a late attach' );
like( $console_service, qr/^Environment=COLUMNS=80$/m,
    'status console fixes the serial width' );
like( $console_service, qr/^Environment=LINES=24$/m,
    'status console fixes the serial height' );
like( $console_service, qr/^TTYPath=\/dev\/%I$/m,
    'status console binds to the machine console' );
unlike( $console_service, qr/xcat\.debug-shell|genesis-debug-shell/,
    'status console has no boot-time debug escape' );

my $console_source_dir =
  'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-console/files/xcat-genesis-console/src';
my $console_source = join "\n", map {
    read_file("$console_source_dir/$_")
} qw(console.h main.c newt_ui.c plain_ui.c shell.c state.c support.c);
ok( !-e File::Spec->catfile(
        $repo_root,
        qw(xCAT-genesis-builder oe meta-xcat-genesis recipes-core xcat-genesis-console files xcat-genesis-console.c)
    ),
    'status console is not kept as a monolithic source file' );
unlike( $console_source, qr/genesis-debug-shell|XCAT_ON_DEMAND_SHELL/,
    'status console only uses the common maintenance-shell launcher' );
like( $console_source, qr/newtDrawRootText\(1, 0, "xCAT Genesis"\)/,
    'status console keeps the product name in the header' );
like( $console_source,
    qr/F1 Help   F2 Diagnostics   F3 Logs   F12 Shell/,
    'status console keeps useful shortcuts in the footer' );
unlike( $console_source, qr/NEWT_KEY_F5|F5 Refresh|Ctrl-L Redraw/,
    'status console omits redundant redraw shortcuts' );
like( $console_source, qr/newtFormSetTimer\(screen\.form, 1000\)/,
    'status console updates timers once per second' );
like( $console_source, qr/"In stage"/,
    'status console labels the stage duration precisely' );
like( $console_source,
    qr/identity = strcmp\(state->node, "unassigned"\).*?state->local_hostname/s,
    'status header falls back to the local hostname before assignment' );
like( $console_source,
    qr/show_serial = useful_identity\(state->serial\).*?state->serial/s,
    'status header includes a useful firmware serial' );
unlike( $console_source,
    qr/xcat_set_text\(context,\s*sizeof\(context\),[^;]*state->architecture/s,
    'status header omits the architecture' );
like( $console_source, qr/newtCenteredWindow\(72, 17, "Genesis status"\)/,
    'main status removes unused top and bottom rows' );
like( $console_source, qr/newtCenteredWindow\(72, 19, "Genesis diagnostics"\)/,
    'F2 opens diagnostics' );
like( $console_source,
    qr/xcat\.bootloader.*?"xnba".*?"xNBA".*?"pxelinux".*?"PXELINUX"/s,
    'diagnostics recognizes xNBA and PXELINUX markers' );
like( $console_source, qr/PXE \(unknown loader\)/,
    'older boot configurations have an honest PXE fallback' );
like( $console_source,
    qr/"Identity\\n\\n".*"\\nManagement network\\n\\n".*"\\nxCAT\\n\\n".*"\\nRuntime\\n\\n"/s,
    'diagnostics group identity, connection, and runtime data' );
like( $console_source,
    qr/(?:add_row\(&screen, LABEL_SERIAL, 4, "Serial"\)|STATUS_FIELD_SERIAL)/,
    'main status includes the hardware serial' );
unlike( $console_source,
    qr/add_row\(&screen, LABEL_(?:RELEASE|SYSTEM|BOOT|EXTENSIONS|HARDWARE|DEBUG),/,
    'inventory and maintenance controls stay off the main status' );
like( $console_source, qr/update_form\(&screen, &(?:state|view), changed\)/,
    'stable status updates only the timers' );
like( $console_source, qr/if \(\+\+redraw >= 30\)/,
    'serial console limits periodic full redraws' );
like( $console_source, qr/newtFormAddHotKey\(screen\.form, NEWT_KEY_F3\)/,
    'F3 opens recent Genesis logs' );
like( $console_source, qr/sd_journal_open\(&journal,/,
    'log view reads the journal without a subprocess' );
like( $console_source, qr/LOG_LINE_COUNT = 128/,
    'log view keeps a bounded serial-friendly history' );
like( $console_source,
    qr/newtListbox\(1, 1, LOG_VIEW_HEIGHT, NEWT_FLAG_SCROLL\).*?newtFormSetTimer\(form, 1000\)/s,
    'log view is scrollable and refreshes once per second' );
like( $console_source,
    qr/bool follow = true.*?NEWT_KEY_UP.*?follow = false/s,
    'upward log navigation pauses following' );
like( $console_source,
    qr/NEWT_KEY_END.*?follow = true.*?newtListboxSetCurrentByKey/s,
    'End resumes log following' );
like( $console_source,
    qr/newtFormAddHotKey\(screen\.form, NEWT_KEY_F12\).*?show_maintenance_shell\(\)/s,
    'F12 opens the maintenance-shell confirmation' );
like( $console_source,
    qr/newtWinChoice\(.*?Open a root maintenance shell\?/s,
    'maintenance shell requires confirmation' );
like( $console_source,
    qr{execl\("/usr/libexec/xcat/genesis-maintenance-shell"},
    'maintenance shell uses a fixed packaged executable' );
like( $console_source,
    qr/FD_CLOEXEC.*?write\(exec_error_pipe\[1\].*?exec_error_size ==/s,
    'maintenance shell reports only direct launch failures' );
unlike( $console_source, qr/WEXITSTATUS/,
    'maintenance shell does not reinterpret the shell exit status' );
unlike( $console_source, qr/\b(?:system|popen)\s*\(/,
    'status console avoids command-string execution' );

my $network_state_service = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/xcat-genesis-network-state.service'
);
like( $network_state_service, qr/^After=NetworkManager\.service$/m,
    'network selection follows NetworkManager' );
like( $network_state_service,
    qr/^Before=xcat-genesis-network-ready\.target$/m,
    'network selection gates Genesis readiness' );

my $register_service = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/xcat-genesis-register.service'
);
like( $register_service,
    qr/^Requires=xcat-genesis-network-ready\.target xcat-genesis-extensions\.service$/m,
    'registration requires Genesis network readiness' );
like( $register_service,
    qr/^After=xcat-genesis-network-ready\.target xcat-genesis-extensions\.service$/m,
    'registration waits for extension verification' );
unlike( $register_service, qr/network-online\.target/,
    'registration avoids generic network readiness' );

my $extension_recipe = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-extensions/xcat-genesis-extensions_1.0.bb'
);
like( $extension_recipe,
    qr/^RDEPENDS:\$\{PN\} = "bash coreutils jq openssl-bin systemd xcat-genesis-init"$/m,
    'extension verifier dependencies are explicit' );

my $extension_loader = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-extensions/files/genesis-sysext'
);
like( $extension_loader, qr/openssl pkeyutl -verify -pubin .* -rawin/s,
    'extension manifests use Ed25519 verification' );
like( $extension_loader, qr/extension architecture .* does not match/,
    'extension architecture mismatches fail closed' );
like( $extension_loader, qr/armv7\*\) printf '%s\\n' armv7hf/,
    'ARMv7 runtimes use the armv7hf extension identity' );
like( $extension_loader, qr/extension kernel release does not match/,
    'kernel extensions require an exact release' );
like( $extension_loader, qr/systemd-sysext refresh/,
    'verified extensions are merged by systemd' );

my $extension_service = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-extensions/files/xcat-genesis-extensions.service'
);
like( $extension_service,
    qr{^ConditionDirectoryNotEmpty=/var/lib/xcat/genesis/extensions$}m,
    'extension loading requires staged artifacts' );
like( $extension_service, qr/^Before=xcat-genesis-register\.service$/m,
    'extensions load before xCAT registration' );

my $extension_class = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/classes-recipe/xcat-genesis-extension.bbclass'
);
like( $extension_class, qr/^inherit sysext-image$/m,
    'extensions use the upstream systemd image class' );
like( $extension_class, qr/^IMAGE_FSTYPES = "squashfs-zst"$/m,
    'extensions are immutable SquashFS images' );
like( $extension_class,
    qr/^XCAT_GENESIS_EXTENSION_ARCHITECTURE \?\?= "\$\{XCAT_GENESIS_ARCHITECTURE\}"$/m,
    'extension manifests use the canonical machine identity' );
like( $extension_class, qr/"armv7hf"/,
    'extension manifests accept the canonical ARMv7 identity' );
unlike( $extension_class, qr/"armv7"/,
    'extension manifests reject the ambiguous ARMv7 identity' );
like( $extension_class, qr/XCAT_GENESIS_EXTENSION_KERNEL_RELEASE/,
    'extension metadata supports kernel ABI pinning' );
like( $extension_class, qr/Restricted Genesis extensions must set LICENSE_FLAGS/,
    'restricted extensions require explicit license acceptance' );
like( $extension_class, qr/"sha256":/,
    'extension manifests record the image digest' );

my $smoke_extension = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-extensions/images/xcat-genesis-extension-smoke.bb'
);
like( $smoke_extension, qr/^XCAT_GENESIS_EXTENSION_NAME = "xcat-smoke"$/m,
    'open smoke extension exercises the build path' );
like( $smoke_extension, qr/^COMPATIBLE_HOST = "x86_64\.\*-linux"$/m,
    'smoke extension is restricted to its declared architecture' );

my $preset = read_file(
    'xCAT-genesis-builder/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files/00-xcat-genesis.preset'
);
is( $preset, "disable getty\@.service\n",
    'preset disables the unused virtual-terminal getty' );

done_testing();
