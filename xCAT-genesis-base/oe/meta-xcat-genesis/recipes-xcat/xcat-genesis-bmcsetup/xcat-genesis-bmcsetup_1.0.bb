SUMMARY = "xCAT Genesis BMC setup action"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

FILESEXTRAPATHS:prepend := "${THISDIR}/../../../../../xCAT-genesis-scripts/usr/bin:"

SRC_URI = "file://bmcsetup \
           file://getipmi \
           file://remoteimmsetup \
           file://updateflag.awk \
           file://genesis-bmcsetup \
           file://genesis-credential-wait \
"
S = "${UNPACKDIR}"

RDEPENDS:${PN} = "bash coreutils gawk ipmitool kmod openssl-bin xcat-genesis-discovery"

do_install() {
    install -d ${D}${libexecdir}/xcat/genesis/actions
    install -m 0755 ${UNPACKDIR}/genesis-bmcsetup \
        ${D}${libexecdir}/xcat/genesis/actions/bmcsetup

    install -d ${D}${libexecdir}/xcat/genesis/bmc-support
    install -m 0755 ${UNPACKDIR}/getipmi \
        ${D}${libexecdir}/xcat/genesis/bmc-support/getipmi
    install -m 0755 ${UNPACKDIR}/remoteimmsetup \
        ${D}${libexecdir}/xcat/genesis/bmc-support/remoteimmsetup
    install -m 0755 ${UNPACKDIR}/updateflag.awk \
        ${D}${libexecdir}/xcat/genesis/bmc-support/updateflag.awk
    install -m 0755 ${UNPACKDIR}/genesis-credential-wait \
        ${D}${libexecdir}/xcat/genesis/bmc-support/allowcred.awk

    install -m 0644 ${UNPACKDIR}/bmcsetup \
        ${D}${libexecdir}/xcat/genesis/bmcsetup
}

FILES:${PN} = "${libexecdir}/xcat/genesis/actions/bmcsetup \
               ${libexecdir}/xcat/genesis/bmc-support \
               ${libexecdir}/xcat/genesis/bmcsetup \
"
