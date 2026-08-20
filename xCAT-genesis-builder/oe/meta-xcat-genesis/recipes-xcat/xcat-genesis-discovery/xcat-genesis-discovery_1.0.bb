SUMMARY = "xCAT Genesis node discovery"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://genesis-discover \
           file://genesis-udp-send.c \
           file://genesis-discovery-callback \
           file://genesis-getcert \
           file://genesis-credential-callback \
           file://xcat-genesis-discovery.socket \
           file://xcat-genesis-discovery@.service \
           file://xcat-genesis-credential.socket \
           file://xcat-genesis-credential@.service \
"
S = "${UNPACKDIR}"

inherit systemd

do_compile() {
    ${CC} ${CPPFLAGS} ${CFLAGS} -std=c17 -Wall -Wextra -Wpedantic -Werror \
        ${LDFLAGS} ${UNPACKDIR}/genesis-udp-send.c \
        -o genesis-udp-send
}

RDEPENDS:${PN} = "bash coreutils gzip iproute2 openssl-bin util-linux-lsblk"

SYSTEMD_SERVICE:${PN} = "xcat-genesis-discovery.socket \
                         xcat-genesis-credential.socket \
"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0755 ${UNPACKDIR}/genesis-discover \
        ${D}${libexecdir}/xcat/genesis-discover
    install -m 0755 ${B}/genesis-udp-send \
        ${D}${libexecdir}/xcat/genesis-udp-send
    install -m 0755 ${UNPACKDIR}/genesis-discovery-callback \
        ${D}${libexecdir}/xcat/genesis-discovery-callback
    install -m 0755 ${UNPACKDIR}/genesis-getcert \
        ${D}${libexecdir}/xcat/genesis-getcert
    install -m 0755 ${UNPACKDIR}/genesis-credential-callback \
        ${D}${libexecdir}/xcat/genesis-credential-callback

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-discovery.socket \
        ${D}${systemd_system_unitdir}/xcat-genesis-discovery.socket
    install -m 0644 ${UNPACKDIR}/xcat-genesis-discovery@.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-discovery@.service
    install -m 0644 ${UNPACKDIR}/xcat-genesis-credential.socket \
        ${D}${systemd_system_unitdir}/xcat-genesis-credential.socket
    install -m 0644 ${UNPACKDIR}/xcat-genesis-credential@.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-credential@.service
}

FILES:${PN} = "${libexecdir}/xcat/genesis-discover \
               ${libexecdir}/xcat/genesis-udp-send \
               ${libexecdir}/xcat/genesis-discovery-callback \
               ${libexecdir}/xcat/genesis-getcert \
               ${libexecdir}/xcat/genesis-credential-callback \
               ${systemd_system_unitdir}/xcat-genesis-discovery.socket \
               ${systemd_system_unitdir}/xcat-genesis-discovery@.service \
               ${systemd_system_unitdir}/xcat-genesis-credential.socket \
               ${systemd_system_unitdir}/xcat-genesis-credential@.service \
"
