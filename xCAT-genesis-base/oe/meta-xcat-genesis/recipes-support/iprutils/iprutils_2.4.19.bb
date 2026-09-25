SUMMARY = "IBM Power RAID adapter utilities"
HOMEPAGE = "https://github.com/bjking1/iprutils"
LICENSE = "CPL-1.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=921fff7eff37a36fc62a0242d67fb9b1"

SRC_URI = "git://github.com/bjking1/iprutils.git;protocol=https;branch=master \
           file://0001-configure-avoid-host-ncurses-config.patch \
           "
SRCREV = "9961e538736a6e81f1072a926c3ad91b8513c8c1"

DEPENDS = "ncurses zlib"
RDEPENDS:${PN} = "bash"

inherit autotools

EXTRA_OECONF = "--without-systemd --without-initscripts --disable-sosreport --disable-iprdumpfmt"

COMPATIBLE_HOST = "powerpc64.*-linux"
