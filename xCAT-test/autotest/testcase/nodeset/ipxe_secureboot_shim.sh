#!/bin/bash
# Read back the UEFI boot script that nodeset writes for one netboot=ipxe node, and report
# whether it names a Secure Boot shim for the kernel it loads.
#
# Usage: ipxe_secureboot_shim.sh <node>
#
# The caller asserts on IPXE_SHIM_OK, so no error message can carry the token of a pass:
#   IPXE_SHIM_OK    the script names a shim after imgload, and the file is served
#   IPXE_SHIM_FAIL  the shim is missing, out of order, or not served, or the case could not read
#                   a boot script at all

node="$1"
if [ -z "$node" ]; then
    echo "IPXE_SHIM_FAIL: no node given"
    exit 1
fi

# lsdef prints nothing for an attribute that is unset, and a pipeline reports the exit status of
# its last command, so "lsdef | sed" answered "unset" for a lookup that failed. The restoration
# writes back what it read, so a failed lookup made this case delete a value the node had. Keep
# the status of lsdef itself, and leave the value in $lookup.
lookup=
read_attr() {
    local out
    if [ "$1" = site ]; then
        out=$(lsdef -t site -i "$2" 2>&1) || return 1
    else
        out=$(lsdef -t node -o "$node" -i "$2" 2>&1) || return 1
    fi
    lookup=$(printf '%s\n' "$out" | sed -n "s/^[[:space:]]*$2=//p" | head -1)
    return 0
}

# Every lookup runs before the first mutation, so a failed one ends the case with nothing to put
# back.
must_read() {
    read_attr "$1" "$2" && return 0
    echo "IPXE_SHIM_FAIL: lsdef -t $1 -i $2 for $node returned non-zero, and a lookup that failed"
    echo "IPXE_SHIM_FAIL: is not an attribute that is unset, so this case changes nothing"
    exit 1
}

must_read node arch
arch=$lookup
# The case file declares arch:x86, so xcattest does not run this on another architecture. A hand
# run can still reach it, and a case that cannot measure must not report a pass.
if [ "$arch" != "x86_64" ]; then
    echo "IPXE_SHIM_FAIL: $node has arch=$arch, and only x86_64 has a UEFI shim"
    exit 1
fi

must_read node netboot
netboot=$lookup
must_read node os
os=$lookup
must_read node provmethod
provmethod=$lookup
# nodeset osimage= writes nodetype.provmethod, profile, os and arch from the osimage row it
# resolved. On the path below the image is named <os>-<arch>-install-compute, so os and arch come
# back as the values read here; profile becomes the row's profile and has to be put back.
must_read node profile
profile=$lookup

must_read site tftpdir
tftpdir=$lookup
[ -n "$tftpdir" ] || tftpdir=/tftpboot
must_read site installdir
installdir=$lookup
[ -n "$installdir" ] || installdir=/install
uefi="$tftpdir/xcat/ipxe/nodes/$node.uefi"

if ! stat_out=$(nodeset "$node" stat 2>&1); then
    echo "IPXE_SHIM_FAIL: nodeset $node stat returned non-zero, so this case cannot read the"
    echo "IPXE_SHIM_FAIL: state it has to put back, and it changes nothing"
    printf '%s\n' "$stat_out"
    exit 1
fi
before=$(printf '%s\n' "$stat_out" | sed -n "s/^$node: *//p" | head -1)
echo "nodeset state of $node before this case: ${before:-empty}, provmethod=${provmethod:-unset}"

# nodeset stat reports chain.currstate verbatim, and a state can carry an argument, so the
# restoration replays the whole string. A state outside this list cannot be replayed: install,
# netboot and statelite are deprecated and the restoring nodeset rejects them, and iscsiboot,
# image, winshell and sysclone read rows this case never saved. The node would keep the
# installation this case configures, so refuse while it is still untouched.
case "$before" in
    boot | offline | shell | shutdown | standby | osimage) ;;
    osimage=?* | runcmd=?* | runimage=?*) ;;
    *)
        echo "IPXE_SHIM_FAIL: nodeset reports $node in state [${before:-empty}], which this case"
        echo "IPXE_SHIM_FAIL: cannot put back, so it changes nothing"
        exit 1
        ;;
esac

# The case reconfigures the node for installation. A restoration that fails leaves it that way,
# so the failure has to reach the caller in place of the result of the case.
restore_done=0
restore_rc=0
netboot_set=
restore_state() {
    [ "$restore_done" = 1 ] && return "$restore_rc"
    restore_done=1
    # Before the nodeset below, or that nodeset writes the boot files of the ipxe method on a node
    # the cluster boots another way.
    if [ -n "$netboot_set" ]; then
        if ! chdef -t node -o "$node" "netboot=$netboot" > /dev/null; then
            echo "IPXE_SHIM_FAIL: chdef -t node -o $node netboot=$netboot returned non-zero, $node keeps the netboot method this case set"
            restore_rc=1
        fi
    fi
    if [ -z "$provmethod" ]; then
        if ! chdef -t node -o "$node" provmethod= "profile=$profile" > /dev/null; then
            echo "IPXE_SHIM_FAIL: chdef -t node -o $node provmethod= profile=$profile returned non-zero, $node keeps the image attributes this case set"
            restore_rc=1
        fi
    fi
    if ! nodeset "$node" "$before"; then
        echo "IPXE_SHIM_FAIL: nodeset $node $before returned non-zero, $node stays configured for installation"
        restore_rc=1
    fi
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
    image="$os-$arch-install-compute"
    if ! lsdef -t osimage -o "$image" > /dev/null 2>&1; then
        echo "IPXE_SHIM_FAIL: $node has no provmethod and osimage $image is not defined, so this"
        echo "IPXE_SHIM_FAIL: case has no boot script to read"
        exit 1
    fi
    destiny="osimage=$image"
fi

# Arm the restoration before the call that changes the state, and not earlier: an exit above this
# line has nothing to put back. Every exit after it passes through the restoration.
trap on_exit EXIT

# Only the ipxe method writes a shim line, so the case sets the method it reads rather than
# reporting a pass on a node that is declared another way. Four of the six confs that carry this
# case declare netboot=xnba on their compute node.
if [ "$netboot" != "ipxe" ]; then
    if ! chdef -t node -o "$node" netboot=ipxe > /dev/null; then
        echo "IPXE_SHIM_FAIL: chdef -t node -o $node netboot=ipxe returned non-zero"
        exit 1
    fi
    netboot_set=1
fi

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
