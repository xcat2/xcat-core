SUMMARY = "xCAT Genesis systemd units"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://00-xcat-genesis.preset \
           file://genesis-functions \
           file://genesis-maintenance-shell \
           file://genesis-action \
           file://genesis-metrics \
           file://genesis-network-refresh \
           file://genesis-network-state \
           file://genesis-register \
           file://genesis-status \
           file://xcat-genesis-action.service \
           file://xcat-genesis-metrics.service \
           file://xcat-genesis-network-ready.target \
           file://xcat-genesis-network-state.service \
           file://xcat-genesis-register.service \
"
S = "${UNPACKDIR}"

inherit systemd

RDEPENDS:${PN} = "bash coreutils ipmitool iproute2 networkmanager-nmcli util-linux-logger xcat-genesis-discovery xcat-genesis-protocol"

SYSTEMD_SERVICE:${PN} = "xcat-genesis-action.service \
                         xcat-genesis-metrics.service \
                         xcat-genesis-network-ready.target \
                         xcat-genesis-register.service \
"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0644 ${UNPACKDIR}/genesis-functions \
        ${D}${libexecdir}/xcat/genesis-functions
    install -m 0755 ${UNPACKDIR}/genesis-maintenance-shell \
        ${D}${libexecdir}/xcat/genesis-maintenance-shell
    install -m 0755 ${UNPACKDIR}/genesis-action \
        ${D}${libexecdir}/xcat/genesis-action
    install -m 0755 ${UNPACKDIR}/genesis-metrics \
        ${D}${libexecdir}/xcat/genesis-metrics
    install -m 0755 ${UNPACKDIR}/genesis-network-refresh \
        ${D}${libexecdir}/xcat/genesis-network-refresh
    install -m 0755 ${UNPACKDIR}/genesis-network-state \
        ${D}${libexecdir}/xcat/genesis-network-state
    install -m 0755 ${UNPACKDIR}/genesis-register \
        ${D}${libexecdir}/xcat/genesis-register
    install -m 0755 ${UNPACKDIR}/genesis-status \
        ${D}${libexecdir}/xcat/genesis-status

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-action.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-action.service
    install -m 0644 ${UNPACKDIR}/xcat-genesis-metrics.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-metrics.service
    install -m 0644 ${UNPACKDIR}/xcat-genesis-network-ready.target \
        ${D}${systemd_system_unitdir}/xcat-genesis-network-ready.target
    install -m 0644 ${UNPACKDIR}/xcat-genesis-network-state.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-network-state.service
    install -m 0644 ${UNPACKDIR}/xcat-genesis-register.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-register.service

    install -d ${D}${systemd_unitdir}/system-preset
    install -m 0644 ${UNPACKDIR}/00-xcat-genesis.preset \
        ${D}${systemd_unitdir}/system-preset/00-xcat-genesis.preset
}

FILES:${PN} = "${libexecdir}/xcat/genesis-maintenance-shell \
               ${libexecdir}/xcat/genesis-functions \
               ${libexecdir}/xcat/genesis-action \
               ${libexecdir}/xcat/genesis-metrics \
               ${libexecdir}/xcat/genesis-network-refresh \
               ${libexecdir}/xcat/genesis-network-state \
               ${libexecdir}/xcat/genesis-register \
               ${libexecdir}/xcat/genesis-status \
               ${systemd_system_unitdir}/xcat-genesis-action.service \
               ${systemd_system_unitdir}/xcat-genesis-metrics.service \
               ${systemd_system_unitdir}/xcat-genesis-network-ready.target \
               ${systemd_system_unitdir}/xcat-genesis-network-state.service \
               ${systemd_system_unitdir}/xcat-genesis-register.service \
               ${systemd_unitdir}/system-preset/00-xcat-genesis.preset \
"
