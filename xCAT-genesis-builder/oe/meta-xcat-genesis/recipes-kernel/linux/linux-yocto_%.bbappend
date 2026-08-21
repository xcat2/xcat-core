FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

COMPATIBLE_MACHINE:xcat-genesis-x86-64 = "^xcat-genesis-x86-64$"
KMACHINE:xcat-genesis-x86-64 = "qemux86-64"
KBRANCH:xcat-genesis-x86-64 = "v6.18/standard/base"

SRC_URI:append:xcat-genesis-x86-64 = " \
    file://xcat-genesis-x86-common.cfg \
    file://xcat-genesis-x86-64.cfg \
"
KERNEL_FEATURES:append:xcat-genesis-x86-64 = " cfg/paravirt_kvm.scc"

COMPATIBLE_MACHINE:xcat-genesis-x86 = "^xcat-genesis-x86$"
KMACHINE:xcat-genesis-x86 = "qemux86"
KBRANCH:xcat-genesis-x86 = "v6.18/standard/base"

SRC_URI:append:xcat-genesis-x86 = " \
    file://0001-qemu-x86-use-i686-baseline.patch;apply=no \
    file://xcat-genesis-x86-common.cfg \
    file://xcat-genesis-x86.cfg \
"
KERNEL_FEATURES:append:xcat-genesis-x86 = " cfg/paravirt_kvm.scc"

do_kernel_metadata:prepend:xcat-genesis-x86() {
    metadata=${UNPACKDIR}/${KMETA}/bsp/common-pc/common-pc-cpu.cfg
    if grep -qx 'CONFIG_MPENTIUMM=y' "$metadata"; then
        patch -p1 -d ${UNPACKDIR}/${KMETA} \
            < ${UNPACKDIR}/0001-qemu-x86-use-i686-baseline.patch
    fi
}

COMPATIBLE_MACHINE:xcat-genesis-armv7hf = "^xcat-genesis-armv7hf$"
KMACHINE:xcat-genesis-armv7hf = "qemuarma15"
KBRANCH:xcat-genesis-armv7hf = "v6.18/standard/base"
SRCREV_machine:xcat-genesis-armv7hf = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"
SRC_URI:append:xcat-genesis-armv7hf = " file://xcat-genesis-armv7hf.cfg"

COMPATIBLE_MACHINE:xcat-genesis-aarch64 = "^xcat-genesis-aarch64$"
KMACHINE:xcat-genesis-aarch64 = "qemuarm64"
KBRANCH:xcat-genesis-aarch64 = "v6.18/standard/base"
SRCREV_machine:xcat-genesis-aarch64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"
SRC_URI:append:xcat-genesis-aarch64 = " file://xcat-genesis-aarch64.cfg"

COMPATIBLE_MACHINE:xcat-genesis-riscv64 = "^xcat-genesis-riscv64$"
KMACHINE:xcat-genesis-riscv64 = "qemuriscv64"
KBRANCH:xcat-genesis-riscv64 = "v6.18/standard/base"
SRCREV_machine:xcat-genesis-riscv64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"
SRC_URI:append:xcat-genesis-riscv64 = " file://xcat-genesis-riscv64.cfg"

COMPATIBLE_MACHINE:xcat-genesis-ppc64le = "^xcat-genesis-ppc64le$"
KMACHINE:xcat-genesis-ppc64le = "qemuppc64"
KBRANCH:xcat-genesis-ppc64le = "v6.18/standard/base"
SRCREV_machine:xcat-genesis-ppc64le = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"

SRC_URI:append:xcat-genesis-ppc64le = " \
    file://0001-qemu-ppc64-drop-removed-crc32-option.patch;apply=no \
    file://xcat-genesis-powerpc64.cfg \
"

do_kernel_metadata:prepend:xcat-genesis-ppc64le() {
    metadata=${UNPACKDIR}/${KMETA}/bsp/qemu-ppc64/qemu-ppc64.cfg
    if grep -qx 'CONFIG_CRC32_SLICEBY8=y' "$metadata"; then
        patch -p1 -d ${UNPACKDIR}/${KMETA} \
            < ${UNPACKDIR}/0001-qemu-ppc64-drop-removed-crc32-option.patch
    fi
}

COMPATIBLE_MACHINE:xcat-genesis-ppc64 = "^xcat-genesis-ppc64$"
KMACHINE:xcat-genesis-ppc64 = "qemuppc64"
KBRANCH:xcat-genesis-ppc64 = "v6.18/standard/base"
SRCREV_machine:xcat-genesis-ppc64 = "b1ba5428513b52c2bd6acfd3ad0a910f699bc395"

SRC_URI:append:xcat-genesis-ppc64 = " \
    file://0001-qemu-ppc64-drop-removed-crc32-option.patch;apply=no \
    file://xcat-genesis-powerpc64.cfg \
    file://xcat-genesis-ppc64.cfg \
"

do_kernel_metadata:prepend:xcat-genesis-ppc64() {
    metadata=${UNPACKDIR}/${KMETA}/bsp/qemu-ppc64/qemu-ppc64.cfg
    if grep -qx 'CONFIG_CRC32_SLICEBY8=y' "$metadata"; then
        patch -p1 -d ${UNPACKDIR}/${KMETA} \
            < ${UNPACKDIR}/0001-qemu-ppc64-drop-removed-crc32-option.patch
    fi
}
do_kernel_metadata[depends] += "patch-native:do_populate_sysroot"
