SUMMARY = "Open hardware tools for xCAT Genesis"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

PACKAGE_ARCH = "${MACHINE_ARCH}"

RDEPENDS:${PN} = "\
    curl \
    dosfstools \
    edac-utils \
    e2fsprogs-e2fsck \
    e2fsprogs-mke2fs \
    ethtool \
    hdparm \
    hwloc \
    ipmitool \
    iproute2-rdma \
    jq \
    kexec \
    kernel-modules \
    lldpd \
    lsscsi \
    lvm2 \
    mdadm \
    memtester \
    mstflint \
    nvme-cli \
    parted \
    pciutils \
    rdma-core \
    sg3-utils \
    smartmontools \
    stress-ng \
    usbutils \
    util-linux-blockdev \
    util-linux-lsblk \
    util-linux-sfdisk \
    util-linux-wipefs \
    xcat-genesis-hardware-control \
"

RDEPENDS:${PN}:append:xcat-genesis-x86 = " dmidecode lshw"
RDEPENDS:${PN}:append:xcat-genesis-x86-64 = " dmidecode lshw mcelog"
RDEPENDS:${PN}:append:xcat-genesis-armv7hf = " dmidecode lshw"
RDEPENDS:${PN}:append:xcat-genesis-aarch64 = " dmidecode lshw"
RDEPENDS:${PN}:append:xcat-genesis-ppc64 = " dmidecode xcat-genesis-hardware-control-iprutils"
RDEPENDS:${PN}:append:xcat-genesis-ppc64le = " dmidecode xcat-genesis-hardware-control-iprutils"
RDEPENDS:${PN}:append:xcat-genesis-riscv64 = " lshw"
