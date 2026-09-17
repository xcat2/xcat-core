SUMMARY = "Payload for the xCAT Genesis test extension"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://xcat-extension-smoke"
S = "${UNPACKDIR}"

do_install() {
    install -d ${D}${libexecdir}/xcat/extensions
    install -m 0755 ${UNPACKDIR}/xcat-extension-smoke \
        ${D}${libexecdir}/xcat/extensions/xcat-extension-smoke
}

FILES:${PN} = "${libexecdir}/xcat/extensions/xcat-extension-smoke"
