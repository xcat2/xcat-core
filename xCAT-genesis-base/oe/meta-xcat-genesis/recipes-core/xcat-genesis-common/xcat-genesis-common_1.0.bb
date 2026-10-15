SUMMARY = "xCAT Genesis runtime functions"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

FILESEXTRAPATHS:prepend := "${THISDIR}/../xcat-genesis-init/files:"
SRC_URI = "file://genesis-functions"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "bash util-linux-logger"

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0644 ${UNPACKDIR}/genesis-functions \
        ${D}${libexecdir}/xcat/genesis-functions
}

FILES:${PN} = "${libexecdir}/xcat/genesis-functions"
