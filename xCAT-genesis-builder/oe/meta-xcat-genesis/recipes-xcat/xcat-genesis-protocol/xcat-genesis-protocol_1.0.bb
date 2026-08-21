SUMMARY = "xCAT Genesis protocol clients"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

FILESEXTRAPATHS:prepend := "${THISDIR}/../../../../../xCAT-genesis-scripts/usr/bin:"

SRC_URI = "file://getdestiny \
           file://nextdestiny \
"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "bash openssl-bin"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${UNPACKDIR}/getdestiny ${D}${bindir}/getdestiny
    install -m 0755 ${UNPACKDIR}/nextdestiny ${D}${bindir}/nextdestiny
}
