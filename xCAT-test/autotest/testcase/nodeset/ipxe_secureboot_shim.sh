#!/bin/bash
# Read back the UEFI boot script that nodeset writes for one netboot=ipxe node, and report
# whether it names a Secure Boot shim for the kernel it loads.
#
# Usage: ipxe_secureboot_shim.sh <node>
#
# The caller asserts on one of three tokens, so no error message can carry the token of a pass:
#   IPXE_SHIM_OK        the script names a shim after imgload, and the file is served
#   IPXE_SHIM_SKIPPED   the node is not an x86_64 netboot=ipxe node
#   IPXE_SHIM_FAIL      the shim is missing, out of order, or not served

node="$1"
if [ -z "$node" ]; then
    echo "IPXE_SHIM_FAIL: no node given"
    exit 1
fi

site_value() {
    lsdef -t site -i "$1" 2>/dev/null | sed -n "s/^[[:space:]]*$1=//p"
}
node_value() {
    lsdef -t node -o "$node" -i "$1" 2>/dev/null | sed -n "s/^[[:space:]]*$1=//p"
}

netboot=$(node_value netboot)
arch=$(node_value arch)
if [ "$netboot" != "ipxe" ]; then
    echo "IPXE_SHIM_SKIPPED: $node has netboot=$netboot, and only the ipxe method names a shim"
    exit 0
fi
if [ "$arch" != "x86_64" ]; then
    echo "IPXE_SHIM_SKIPPED: $node has arch=$arch, and only x86_64 has a UEFI shim"
    exit 0
fi

tftpdir=$(site_value tftpdir)
[ -n "$tftpdir" ] || tftpdir=/tftpboot
installdir=$(site_value installdir)
[ -n "$installdir" ] || installdir=/install
uefi="$tftpdir/xcat/ipxe/nodes/$node.uefi"

before=$(nodeset "$node" stat 2>/dev/null | sed -n "s/^$node: *//p" | head -1)
provmethod=$(node_value provmethod)
echo "nodeset state of $node before this case: ${before:-unknown}, provmethod=${provmethod:-unset}"

restore_state() {
    if [ -z "$provmethod" ]; then
        chdef -t node -o "$node" provmethod= > /dev/null
    fi
    case "${before%% *}" in
        boot | offline | shell | standby)
            nodeset "$node" "${before%% *}" || echo "could not put $node back to ${before%% *}"
            ;;
    esac
}

# A hand run reaches this case before any provisioning case has set nodetype.provmethod, so name
# the stateful image of the node here. In a bundle the provisioning cases have already set it.
destiny=osimage
if [ -z "$provmethod" ]; then
    image="$(node_value os)-$arch-install-compute"
    if ! lsdef -t osimage -o "$image" > /dev/null 2>&1; then
        echo "IPXE_SHIM_SKIPPED: $node has no provmethod and osimage $image is not defined"
        exit 0
    fi
    destiny="osimage=$image"
fi

if ! nodeset "$node" "$destiny"; then
    echo "IPXE_SHIM_FAIL: nodeset $node $destiny returned non-zero"
    restore_state
    exit 1
fi
if [ ! -f "$uefi" ]; then
    echo "IPXE_SHIM_FAIL: nodeset wrote no $uefi"
    restore_state
    exit 1
fi
echo "--- $uefi ---"
cat "$uefi"
echo "--- end ---"

# iPXE loads a kernel that carries an EFI stub with imgload. The shim command reads the image
# that imgload selected, so the shim line must follow it.
if ! grep -q '^imgload kernel$' "$uefi"; then
    echo "IPXE_SHIM_FAIL: the UEFI script of $node selects no kernel image with imgload"
    restore_state
    exit 1
fi
after=$(awk '/^imgload kernel$/ { if ((getline line) > 0) { print line } exit }' "$uefi")
case "$after" in
    "shim http://"*) ;;
    *)
        echo "IPXE_SHIM_FAIL: the line after imgload is [$after], not a shim command"
        restore_state
        exit 1
        ;;
esac

# iPXE fetches the shim over HTTP, so the path has to resolve to a file the web server serves.
urlpath=$(printf '%s\n' "$after" | sed -n 's|^shim http://[^/]*\(/.*\)$|\1|p')
case "$urlpath" in
    /install/*) shimfile="$installdir/${urlpath#/install/}" ;;
    /tftpboot/*) shimfile="$tftpdir/${urlpath#/tftpboot/}" ;;
    *)
        echo "IPXE_SHIM_FAIL: the shim path [$urlpath] is under neither /install nor /tftpboot"
        restore_state
        exit 1
        ;;
esac
if [ ! -f "$shimfile" ]; then
    echo "IPXE_SHIM_FAIL: the script names $urlpath and $shimfile does not exist"
    restore_state
    exit 1
fi

restore_state
echo "IPXE_SHIM_OK: $after resolves to $shimfile"
exit 0
