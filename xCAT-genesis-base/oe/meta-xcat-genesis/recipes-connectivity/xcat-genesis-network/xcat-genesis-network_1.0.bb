SUMMARY = "xCAT Genesis network configuration"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://10-xcat-genesis.conf \
           file://genesis-duid \
           file://xcat-genesis-duid.service \
"
S = "${UNPACKDIR}"

inherit systemd

RDEPENDS:${PN} = "bash coreutils networkmanager-daemon networkmanager-nmcli util-linux-logger"

SYSTEMD_SERVICE:${PN} = "xcat-genesis-duid.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${sysconfdir}/NetworkManager/conf.d
    install -m 0644 ${UNPACKDIR}/10-xcat-genesis.conf \
        ${D}${sysconfdir}/NetworkManager/conf.d/10-xcat-genesis.conf

    install -d ${D}${libexecdir}/xcat
    install -m 0755 ${UNPACKDIR}/genesis-duid \
        ${D}${libexecdir}/xcat/genesis-duid

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-duid.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-duid.service
}

FILES:${PN} = "${sysconfdir}/NetworkManager/conf.d/10-xcat-genesis.conf \
               ${libexecdir}/xcat/genesis-duid \
               ${systemd_system_unitdir}/xcat-genesis-duid.service \
"
