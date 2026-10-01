DEFAULTTUNE ?= "s390x"

TUNEVALID[m64] = "64-bit z/Architecture ABI"
TUNEVALID[bigendian] = "Big-endian byte order"
TUNEVALID[z10] = "IBM System z10 instruction set"

TUNE_ARCH = "s390x"
TUNE_PKGARCH = "${TUNE_PKGARCH:tune-${DEFAULTTUNE}}"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'm64', ' -m64', '', d)}"
TUNE_CCARGS .= "${@bb.utils.contains('TUNE_FEATURES', 'z10', ' -march=z10 -mtune=z10', '', d)}"

AVAILTUNES += "s390x"
TUNE_FEATURES:tune-s390x = "m64 bigendian z10"
BASE_LIB:tune-s390x = "lib64"
BASELIB:libc-glibc:s390x = "lib64"
TUNE_PKGARCH:tune-s390x = "s390x"
PACKAGE_EXTRA_ARCHS:tune-s390x = "s390x"

def xcat_genesis_s390x_siteinfo(archinfo, osinfo, targetinfo, d):
    archinfo["s390x"] = "endian-big bit-64"
    return archinfo, osinfo, targetinfo

SITEINFO_EXTRA_DATAFUNCS += "xcat_genesis_s390x_siteinfo"

def xcat_genesis_s390x_packageqa_machdata(machdata, d):
    machdata["linux"]["s390x"] = (22, 0, 0, False, 64)
    return machdata

PACKAGEQA_EXTRA_MACHDEFFUNCS += "xcat_genesis_s390x_packageqa_machdata"
