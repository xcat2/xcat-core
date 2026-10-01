SUMMARY = "IBM Z network configuration utility"
HOMEPAGE = "https://github.com/ibm-s390-linux/s390-tools"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://LICENSE;md5=f5118f167b055bfd7c3450803f1847af"

SRC_URI = "git://github.com/ibm-s390-linux/s390-tools;protocol=https;branch=master;tag=v${PV}"
SRCREV = "5e07b30bdf67623e7a6d3850e26208b642d416d7"

COMPATIBLE_HOST = "s390x.*-linux"

RDEPENDS:${PN} = "bash coreutils findutils gawk grep kmod sed udev util-linux-getopt util-linux-logger"

do_compile[noexec] = "1"

do_install() {
    install -d ${D}${base_sbindir} ${D}${nonarch_base_libdir}/s390-tools
    sed 's/%S390_TOOLS_VERSION%/${PV}/g' ${S}/zconf/znetconf \
        >${D}${base_sbindir}/znetconf
    chmod 0755 ${D}${base_sbindir}/znetconf
    install -m 0755 ${S}/zconf/lsznet.raw \
        ${D}${nonarch_base_libdir}/s390-tools/lsznet.raw
    install -m 0755 ${S}/zconf/znetcontrolunits \
        ${D}${nonarch_base_libdir}/s390-tools/znetcontrolunits
}

FILES:${PN} = "${base_sbindir}/znetconf ${nonarch_base_libdir}/s390-tools"
