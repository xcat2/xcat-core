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

# The case reconfigures the node for installation. A restoration that fails leaves it that way,
# so the failure has to reach the caller in place of the result of the case.
restore_done=0
restore_rc=0
restore_state() {
    [ "$restore_done" = 1 ] && return "$restore_rc"
    restore_done=1
    if [ -z "$provmethod" ]; then
        if ! chdef -t node -o "$node" provmethod= > /dev/null; then
            echo "IPXE_SHIM_FAIL: chdef -t node -o $node provmethod= returned non-zero, $node keeps the provmethod this case set"
            restore_rc=1
        fi
    fi
    case "${before%% *}" in
        boot | offline | shell | standby)
            if ! nodeset "$node" "${before%% *}"; then
                echo "IPXE_SHIM_FAIL: nodeset $node ${before%% *} returned non-zero, $node stays configured for installation"
                restore_rc=1
            fi
            ;;
    esac
    return "$restore_rc"
}

on_exit() {
    status=$?
    restore_state || status=1
    exit "$status"
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

# Arm the restoration before the call that changes the state, and not earlier: a skip above this
# line has nothing to put back. Every exit after it passes through the restoration.
trap on_exit EXIT

if ! nodeset "$node" "$destiny"; then
    echo "IPXE_SHIM_FAIL: nodeset $node $destiny returned non-zero"
    exit 1
fi
if [ ! -f "$uefi" ]; then
    echo "IPXE_SHIM_FAIL: nodeset wrote no $uefi"
    exit 1
fi
echo "--- $uefi ---"
cat "$uefi"
echo "--- end ---"

# iPXE loads a kernel that carries an EFI stub with imgload. The shim command reads the image
# that imgload selected, so the shim line must follow it.
if ! grep -q '^imgload kernel$' "$uefi"; then
    echo "IPXE_SHIM_FAIL: the UEFI script of $node selects no kernel image with imgload"
    exit 1
fi
after=$(awk '/^imgload kernel$/ { if ((getline line) > 0) { print line } exit }' "$uefi")
case "$after" in
    "shim http://"*) ;;
    *)
        echo "IPXE_SHIM_FAIL: the line after imgload is [$after], not a shim command"
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
        exit 1
        ;;
esac
if [ ! -f "$shimfile" ]; then
    echo "IPXE_SHIM_FAIL: the script names $urlpath and $shimfile does not exist"
    exit 1
fi

restore_state || exit 1
echo "IPXE_SHIM_OK: $after resolves to $shimfile"
exit 0
