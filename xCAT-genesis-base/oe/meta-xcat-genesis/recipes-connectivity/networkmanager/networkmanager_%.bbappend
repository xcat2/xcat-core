EXTRA_OEMESON:remove = "-Dtests=yes"
EXTRA_OEMESON:append = " -Dtests=no"

do_install:append() {
    sed -i '/^Also=NetworkManager-wait-online.service$/d' \
        ${D}${systemd_system_unitdir}/NetworkManager.service
}
