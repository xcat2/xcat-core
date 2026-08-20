SUMMARY = "Signed system extension loader for xCAT Genesis"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://genesis-sysext \
           file://xcat-genesis-extensions.service \
"
S = "${UNPACKDIR}"

inherit systemd

RDEPENDS:${PN} = "bash coreutils jq openssl-bin systemd xcat-genesis-init"

SYSTEMD_SERVICE:${PN} = "xcat-genesis-extensions.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0755 ${UNPACKDIR}/genesis-sysext \
        ${D}${libexecdir}/xcat/genesis-sysext

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-extensions.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-extensions.service

    install -d ${D}${datadir}/xcat/genesis/extension-keys
}

FILES:${PN} = "${libexecdir}/xcat/genesis-sysext \
               ${systemd_system_unitdir}/xcat-genesis-extensions.service \
               ${datadir}/xcat/genesis/extension-keys \
"
