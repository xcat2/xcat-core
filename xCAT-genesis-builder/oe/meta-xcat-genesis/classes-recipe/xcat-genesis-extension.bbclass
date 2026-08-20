inherit sysext-image

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "squashfs-zst"
IMAGE_ROOTFS_SIZE ?= "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"

XCAT_GENESIS_EXTENSION_NAME ??= "${BPN}"
XCAT_GENESIS_EXTENSION_VERSION ??= "${PV}"
XCAT_GENESIS_EXTENSION_ARCHITECTURE ??= "${XCAT_GENESIS_ARCHITECTURE}"
XCAT_GENESIS_EXTENSION_KEY_ID ??= "xcat-release"
XCAT_GENESIS_EXTENSION_LICENSE_CLASS ??= "open"
XCAT_GENESIS_EXTENSION_CAPABILITIES ??= "[]"
XCAT_GENESIS_EXTENSION_PCI_IDS ??= "[]"
XCAT_GENESIS_EXTENSION_KERNEL_MODULES ??= "false"
XCAT_GENESIS_EXTENSION_KERNEL_RELEASE ??= ""

python __anonymous() {
    import json
    import re

    name = d.getVar("XCAT_GENESIS_EXTENSION_NAME")
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]{0,63}", name):
        bb.fatal("Invalid Genesis extension name: %s" % name)

    version = d.getVar("XCAT_GENESIS_EXTENSION_VERSION")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]{0,63}", version):
        bb.fatal("Invalid Genesis extension version: %s" % version)

    key_id = d.getVar("XCAT_GENESIS_EXTENSION_KEY_ID")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}", key_id):
        bb.fatal("Invalid Genesis extension key ID: %s" % key_id)

    architecture = d.getVar("XCAT_GENESIS_EXTENSION_ARCHITECTURE")
    architectures = {
        "x86", "x86_64", "ppc64", "ppc64le", "armv7hf", "aarch64", "riscv64"
    }
    if architecture not in architectures:
        bb.fatal("Invalid Genesis extension architecture: %s" % architecture)

    license_class = d.getVar("XCAT_GENESIS_EXTENSION_LICENSE_CLASS")
    if license_class not in {"open", "redistributable", "restricted"}:
        bb.fatal("Invalid Genesis extension license class: %s" % license_class)
    if license_class == "restricted" and not (d.getVar("LICENSE_FLAGS") or "").strip():
        bb.fatal("Restricted Genesis extensions must set LICENSE_FLAGS")

    kernel_modules = d.getVar("XCAT_GENESIS_EXTENSION_KERNEL_MODULES")
    if kernel_modules not in {"true", "false"}:
        bb.fatal("XCAT_GENESIS_EXTENSION_KERNEL_MODULES must be true or false")
    if kernel_modules == "true" and not d.getVar("XCAT_GENESIS_EXTENSION_KERNEL_RELEASE"):
        bb.fatal("Kernel extensions must declare XCAT_GENESIS_EXTENSION_KERNEL_RELEASE")

    patterns = {
        "XCAT_GENESIS_EXTENSION_CAPABILITIES": r"[a-z][a-z0-9.-]*",
        "XCAT_GENESIS_EXTENSION_PCI_IDS": r"[0-9a-f]{4}:[0-9a-f]{4}",
    }
    for variable, pattern in patterns.items():
        try:
            value = json.loads(d.getVar(variable))
        except ValueError as error:
            bb.fatal("Invalid JSON in %s: %s" % (variable, error))
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            bb.fatal("%s must be a JSON string array" % variable)
        if not all(re.fullmatch(pattern, item) for item in value):
            bb.fatal("Invalid value in %s" % variable)
}

xcat_genesis_write_extension_manifest() {
    image=${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.squashfs-zst
    manifest=${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.manifest.json
    test -f "$image"

    kernel_release=null
    if [ "${XCAT_GENESIS_EXTENSION_KERNEL_MODULES}" = true ]; then
        kernel_release='"${XCAT_GENESIS_EXTENSION_KERNEL_RELEASE}"'
    fi

    digest=$(sha256sum "$image" | awk '{print $1}')
    {
        printf '%s\n' '{'
        printf '  "architecture": "%s",\n' '${XCAT_GENESIS_EXTENSION_ARCHITECTURE}'
        printf '  "capabilities": %s,\n' '${XCAT_GENESIS_EXTENSION_CAPABILITIES}'
        printf '  "genesis_release": "%s",\n' '${DISTRO_VERSION}'
        printf '  "kernel_modules": %s,\n' '${XCAT_GENESIS_EXTENSION_KERNEL_MODULES}'
        printf '  "kernel_release": %s,\n' "$kernel_release"
        printf '  "key_id": "%s",\n' '${XCAT_GENESIS_EXTENSION_KEY_ID}'
        printf '  "license_class": "%s",\n' '${XCAT_GENESIS_EXTENSION_LICENSE_CLASS}'
        printf '  "name": "%s",\n' '${XCAT_GENESIS_EXTENSION_NAME}'
        printf '  "pci_ids": %s,\n' '${XCAT_GENESIS_EXTENSION_PCI_IDS}'
        printf '%s\n' '  "schema": 1,'
        printf '  "sha256": "%s",\n' "$digest"
        printf '  "version": "%s"\n' '${XCAT_GENESIS_EXTENSION_VERSION}'
        printf '%s\n' '}'
    } >"$manifest"
}

IMAGE_POSTPROCESS_COMMAND += "xcat_genesis_write_extension_manifest;"
