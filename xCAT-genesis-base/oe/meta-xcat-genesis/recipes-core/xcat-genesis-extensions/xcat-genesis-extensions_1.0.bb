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
XCAT_GENESIS_EXTENSION_BUNDLE ??= ""

do_install() {
    install -d ${D}${libexecdir}/xcat
    install -m 0755 ${UNPACKDIR}/genesis-sysext \
        ${D}${libexecdir}/xcat/genesis-sysext

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${UNPACKDIR}/xcat-genesis-extensions.service \
        ${D}${systemd_system_unitdir}/xcat-genesis-extensions.service

    install -d ${D}${datadir}/xcat/genesis/extension-keys \
        ${D}${localstatedir}/lib/xcat/genesis/extensions

    if [ -n "${XCAT_GENESIS_EXTENSION_BUNDLE}" ]; then
        case "${XCAT_GENESIS_EXTENSION_BUNDLE}" in
            *[!A-Za-z0-9._-]*|.|..) bbfatal "Invalid Genesis extension bundle name" ;;
        esac
        bundle=${UNPACKDIR}/${XCAT_GENESIS_EXTENSION_BUNDLE}
        test -d "$bundle/extension-keys" \
            || bbfatal "Genesis extension bundle has no trust store"
        test -d "$bundle/extensions" \
            || bbfatal "Genesis extension bundle has no extensions"
        cp -R --no-preserve=ownership "$bundle/extension-keys/." \
            ${D}${datadir}/xcat/genesis/extension-keys/
        cp -R --no-preserve=ownership "$bundle/extensions/." \
            ${D}${localstatedir}/lib/xcat/genesis/extensions/
    fi
}

FILES:${PN} = "${libexecdir}/xcat/genesis-sysext \
               ${systemd_system_unitdir}/xcat-genesis-extensions.service \
               ${datadir}/xcat/genesis/extension-keys \
               ${localstatedir}/lib/xcat/genesis/extensions \
"
