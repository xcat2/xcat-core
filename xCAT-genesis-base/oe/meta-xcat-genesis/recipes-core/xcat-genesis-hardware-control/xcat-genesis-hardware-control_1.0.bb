SUMMARY = "Hardware provider dispatcher for xCAT Genesis"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

SRC_URI = "file://genesis-hardware \
           file://iprutils.json \
           file://mstflint.json \
           file://nvme.json \
           file://provider-iprutils \
           file://provider-mstflint \
           file://provider-nvme \
"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "bash coreutils jq mstflint nvme-cli util-linux-flock"

PACKAGES:prepend:xcat-genesis-ppc64 = "${PN}-iprutils "
PACKAGES:prepend:xcat-genesis-ppc64le = "${PN}-iprutils "
RDEPENDS:${PN}-iprutils:xcat-genesis-ppc64 = "${PN} bash iprutils"
RDEPENDS:${PN}-iprutils:xcat-genesis-ppc64le = "${PN} bash iprutils"

do_install() {
    install -d ${D}${libexecdir}/xcat/genesis/providers
    install -m 0755 ${UNPACKDIR}/genesis-hardware \
        ${D}${libexecdir}/xcat/genesis-hardware
    install -m 0755 ${UNPACKDIR}/provider-mstflint \
        ${D}${libexecdir}/xcat/genesis/providers/mstflint
    install -m 0755 ${UNPACKDIR}/provider-nvme \
        ${D}${libexecdir}/xcat/genesis/providers/nvme

    install -d ${D}${datadir}/xcat/genesis/providers
    install -m 0644 ${UNPACKDIR}/mstflint.json \
        ${D}${datadir}/xcat/genesis/providers/mstflint.json
    install -m 0644 ${UNPACKDIR}/nvme.json \
        ${D}${datadir}/xcat/genesis/providers/nvme.json
}

do_install:append:xcat-genesis-ppc64() {
    install -m 0755 ${UNPACKDIR}/provider-iprutils \
        ${D}${libexecdir}/xcat/genesis/providers/iprutils
    install -m 0644 ${UNPACKDIR}/iprutils.json \
        ${D}${datadir}/xcat/genesis/providers/iprutils.json
}

do_install:append:xcat-genesis-ppc64le() {
    install -m 0755 ${UNPACKDIR}/provider-iprutils \
        ${D}${libexecdir}/xcat/genesis/providers/iprutils
    install -m 0644 ${UNPACKDIR}/iprutils.json \
        ${D}${datadir}/xcat/genesis/providers/iprutils.json
}

FILES:${PN} = "${libexecdir}/xcat/genesis-hardware \
               ${libexecdir}/xcat/genesis/providers \
               ${datadir}/xcat/genesis/providers \
"

FILES:${PN}-iprutils:xcat-genesis-ppc64 = "${libexecdir}/xcat/genesis/providers/iprutils \
                                          ${datadir}/xcat/genesis/providers/iprutils.json \
"

FILES:${PN}-iprutils:xcat-genesis-ppc64le = "${libexecdir}/xcat/genesis/providers/iprutils \
                                            ${datadir}/xcat/genesis/providers/iprutils.json \
"
