SUMMARY = "xCAT Genesis network configuration"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://10-xcat-genesis.conf"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "networkmanager-daemon networkmanager-nmcli"

do_install() {
    install -d ${D}${sysconfdir}/NetworkManager/conf.d
    install -m 0644 ${UNPACKDIR}/10-xcat-genesis.conf \
        ${D}${sysconfdir}/NetworkManager/conf.d/10-xcat-genesis.conf
}

FILES:${PN} = "${sysconfdir}/NetworkManager/conf.d/10-xcat-genesis.conf"
