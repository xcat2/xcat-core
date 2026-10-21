SUMMARY = "xCAT Genesis status console"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://xcat-genesis-console \
           file://xcat-genesis-console@.service \
"
S = "${UNPACKDIR}/xcat-genesis-console"

DEPENDS = "libnewt systemd"
RDEPENDS:${PN} = "libnewt libsystemd ncurses-terminfo-base xcat-genesis-init"

inherit meson pkgconfig systemd

SYSTEMD_SERVICE:${PN} = "xcat-genesis-console@${XCAT_GENESIS_CONSOLE_TTY}.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install:append() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-console@.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-console@.service
}

FILES:${PN} = "${sbindir}/xcat-genesis-console \
               ${systemd_system_unitdir}/xcat-genesis-console@.service \
"
