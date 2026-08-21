SUMMARY = "Open test extension for xCAT Genesis"
LICENSE = "EPL-1.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/EPL-1.0;md5=57f8d5e2b3e98ac6e088986c12bf94e6"

inherit xcat-genesis-extension

IMAGE_INSTALL = "xcat-genesis-extension-smoke-payload"

XCAT_GENESIS_EXTENSION_NAME = "xcat-smoke"
XCAT_GENESIS_EXTENSION_ARCHITECTURE = "x86_64"
XCAT_GENESIS_EXTENSION_CAPABILITIES = '["diagnostic.smoke"]'

COMPATIBLE_HOST = "x86_64.*-linux"
