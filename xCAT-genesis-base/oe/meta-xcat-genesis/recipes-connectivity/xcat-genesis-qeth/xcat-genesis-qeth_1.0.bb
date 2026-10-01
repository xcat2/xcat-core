SUMMARY = "xCAT Genesis qeth activation"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://genesis-qeth \
           file://xcat-genesis-qeth.service \
"
S = "${UNPACKDIR}"

COMPATIBLE_HOST = "s390x.*-linux"

inherit systemd

RDEPENDS:${PN} = "bash s390-tools-znetconf util-linux-logger xcat-genesis-init"

SYSTEMD_SERVICE:${PN} = "xcat-genesis-qeth.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0755 ${UNPACKDIR}/genesis-qeth \
        ${D}${libexecdir}/xcat/genesis-qeth

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-qeth.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-qeth.service
}

FILES:${PN} = "${libexecdir}/xcat/genesis-qeth \
               ${systemd_system_unitdir}/xcat-genesis-qeth.service \
"
