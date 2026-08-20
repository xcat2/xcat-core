SUMMARY = "xCAT Genesis netboot image"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

IMAGE_INSTALL = "packagegroup-core-boot packagegroup-xcat-genesis-hardware os-release systemd-conf udev-hwdb xcat-genesis-console xcat-genesis-discovery xcat-genesis-extensions xcat-genesis-init xcat-genesis-network xcat-genesis-protocol"
IMAGE_LINGUAS = " "
IMAGE_FEATURES = ""

inherit core-image

IMAGE_ROOTFS_SIZE = "65536"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
