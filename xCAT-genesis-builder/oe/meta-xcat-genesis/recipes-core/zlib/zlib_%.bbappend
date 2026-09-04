FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append:s390x = " file://0001-configure-disable-s390x-crcvx-by-default.patch"
