SUMMARY = "Firmware tools for NVIDIA and Mellanox network adapters"
HOMEPAGE = "https://github.com/Mellanox/mstflint"
LICENSE = "Linux-OpenIB & MIT & BSD-2-Clause"
LIC_FILES_CHKSUM = "\
    file://LICENSE;md5=79e20039679d6414176a6a04804e40be \
    file://ext_libs/json/LICENSE;md5=b3fc92db0084f98e349b55033958325e \
    file://ext_libs/muparser/muParser.h;beginline=1;endline=27;md5=2d47adf7e1fcdedc5cc8bc4a7292bd09 \
"

SRC_URI = "\
    git://github.com/Mellanox/mstflint.git;protocol=https;branch=master \
    file://0001-python-tools-use-libtool-objects.patch \
"
SRCREV = "b9d9e844a14ae1c85cb90c76ccd4a56a0eccd599"

inherit autotools pkgconfig

DEPENDS = "sqlite3"
RDEPENDS:${PN} = "python3-modules"

PACKAGECONFIG ??= "adb cables dc inband openssl"
PACKAGECONFIG[adb] = "--enable-adb-generic-tools,--disable-adb-generic-tools,expat xz"
PACKAGECONFIG[cables] = "--enable-cables,--disable-cables"
PACKAGECONFIG[dc] = "--enable-dc,--disable-dc,zlib"
PACKAGECONFIG[inband] = "--enable-inband,--disable-inband,rdma-core"
PACKAGECONFIG[openssl] = "--enable-openssl,--disable-openssl,openssl"
PACKAGECONFIG[rdmem] = "--enable-rdmem,--disable-rdmem,rdma-core"

EXTRA_OECONF = "\
    --disable-dpa \
    --disable-fw-mgr \
    --disable-i2c \
    --disable-nvfwreset \
    --disable-nvml \
    --disable-vfio \
    --disable-xml2 \
"
