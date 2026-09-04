FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:s390x = " file://50-xcat-s390x.conf"

do_configure:prepend:s390x() {
    install -m 0644 ${UNPACKDIR}/50-xcat-s390x.conf ${S}/Configurations/
}
