#!/bin/bash
###############################################################################
# nic_cfg.sh - backend-aware NIC-config query/teardown helper for xCAT autotest.
#
# Runs ON the target node. Ship + run it from a test case with xdsh -e, e.g.:
#     xdsh $$CN -e /opt/xcat/share/xcat/tools/autotest/testcase/commoncmd/nic_cfg.sh show ens4
#
# Why this exists:
#   confignetwork/confignics/infiniband/HA cases historically verify NIC config by
#   reading /etc/sysconfig/network-scripts/ifcfg-* (Red Hat) or /etc/sysconfig/network
#   (SUSE) or /etc/network/interfaces.d (Ubuntu). On EL10 the
#   NetworkManager-initscripts-ifcfg-rh plugin is gone: NetworkManager is keyfile-only
#   (/etc/NetworkManager/system-connections/*.nmconnection) and the network-scripts dir
#   does not exist, so every ifcfg read comes back empty and the cases fail.
#
#   This helper detects the active backend and emits a NORMALIZED, ifcfg-style
#   "KEY=value" dump (IPADDR=, PREFIX=, BOOTPROTO=, MTU=, ...) regardless of backend,
#   so the existing `check:output=~...` assertions keep matching on every OS. On EL it
#   reads NetworkManager (nmcli + the keyfile); on SUSE/RH it reads ifcfg; on Ubuntu it
#   reads interfaces.d.
#
# Subcommands:
#   show <dev>     normalized config dump for kernel device <dev>
#                  (ens4, bond0, bond0.2, br0, br22, ib0, ...). Also appends the raw
#                  backend config file so extra params are visible/greppable.
#   del  <dev>     remove the xCAT connection / ifcfg for <dev>
#   backup         snapshot the persistent network config under /tmp/backupnet
#   restore        restore the snapshot and reload the active backend
#
# <dev> is the kernel device name the tests already use; on NetworkManager the xCAT
# connection ("xcat-<dev>", "xcat-bond-<name>", "xcat-bridge-<dev>",
# "xcat-vlan-<dev>.<id>", ...) is resolved from the device, so callers never need to
# know the connection naming.
###############################################################################

NMDIR=/etc/NetworkManager/system-connections
RHDIR=/etc/sysconfig/network-scripts
SUSEDIR=/etc/sysconfig/network
UBUDIR=/etc/network/interfaces.d
BACKUP=/tmp/backupnet

detect_backend() {
    if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager 2>/dev/null; then
        echo nm
    elif [ -d "$SUSEDIR" ] && grep -qi suse /etc/*release 2>/dev/null; then
        echo suse
    elif grep -qi ubuntu /etc/*release 2>/dev/null; then
        echo ubuntu
    elif [ -d "$RHDIR" ]; then
        echo rh
    else
        echo unknown
    fi
}

# Resolve a connection's on-disk keyfile path. NM names it "<id>-<uuid>.nmconnection"
# (not just "<id>.nmconnection") whenever a same-named file already exists, so resolve by
# UUID rather than assuming the plain name.
nm_keyfile() {
    local conn=$1 uuid
    uuid=$(nmcli -g connection.uuid connection show "$conn" 2>/dev/null)
    if [ -n "$uuid" ]; then
        grep -l "uuid=$uuid" "$NMDIR"/*.nmconnection 2>/dev/null | head -1
    fi
}

# Resolve the NetworkManager connection name bound to a device.
nm_conn_for_dev() {
    local dev=$1 c cand
    c=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$dev" '$2==d{print $1; exit}')
    [ -z "$c" ] && c=$(nmcli -t -f NAME,DEVICE connection show 2>/dev/null | awk -F: -v d="$dev" '$2==d{print $1; exit}')
    if [ -z "$c" ]; then
        for cand in "xcat-$dev" "xcat-bond-$dev" "xcat-bridge-$dev" "xcat-vlan-$dev"; do
            if nmcli -t -f NAME connection show 2>/dev/null | grep -qx "$cand"; then c=$cand; break; fi
        done
    fi
    echo "$c"
}

nm_show() {
    local dev=$1 conn method addrs a ip pfx mtu kf
    conn=$(nm_conn_for_dev "$dev")
    if [ -z "$conn" ]; then echo "nic_cfg: no NetworkManager connection for device $dev"; return 1; fi
    echo "NAME=$conn"
    echo "DEVICE=$dev"
    method=$(nmcli -g ipv4.method connection show "$conn" 2>/dev/null)
    case "$method" in
        manual) echo "BOOTPROTO=none" ;;
        auto)   echo "BOOTPROTO=dhcp" ;;
        disabled|"") : ;;
        *)      echo "BOOTPROTO=$method" ;;
    esac
    addrs=$(nmcli -g ipv4.addresses connection show "$conn" 2>/dev/null)
    local oldifs="$IFS"; IFS=','
    for a in $addrs; do
        a=$(echo "$a" | tr -d ' ')
        [ -z "$a" ] && continue
        ip=${a%/*}; pfx=${a#*/}
        echo "IPADDR=$ip"
        echo "PREFIX=$pfx"
    done
    IFS="$oldifs"
    mtu=$(nmcli -g 802-3-ethernet.mtu connection show "$conn" 2>/dev/null)
    kf=$(nm_keyfile "$conn")
    if { [ -z "$mtu" ] || [ "$mtu" = "auto" ]; } && [ -n "$kf" ] && [ -r "$kf" ]; then
        mtu=$(awk -F= '/^[[:space:]]*mtu=/{print $2; exit}' "$kf")
    fi
    [ -n "$mtu" ] && [ "$mtu" != "auto" ] && echo "MTU=$mtu"
    # Raw keyfile so anything not normalized above (extra params, slaves, vlan id, ...)
    # is still visible and greppable by the case's check: lines.
    if [ -r "$kf" ]; then echo "# --- $kf ---"; cat "$kf"; fi
}

file_show() {
    # SUSE / legacy-RH / Ubuntu: cat whatever ifcfg/interfaces file matches the device.
    local dev=$1 f found=1
    for f in "$RHDIR"/ifcfg-*"$dev"* "$SUSEDIR"/ifcfg-"$dev" "$UBUDIR"/"$dev" "$UBUDIR"/"$dev":* ; do
        if [ -r "$f" ]; then echo "# --- $f ---"; cat "$f"; found=0; fi
    done
    [ -r /etc/network/interfaces ] && { echo "# --- /etc/network/interfaces ---"; cat /etc/network/interfaces; found=0; }
    return $found
}

nm_del() {
    local dev=$1 conn c
    conn=$(nm_conn_for_dev "$dev")
    [ -n "$conn" ] && nmcli connection delete "$conn" >/dev/null 2>&1
    # Drop every xCAT-created connection referencing this device (the connection itself,
    # its vlan children, and any bond/bridge slave on it), including NM's collision-renamed
    # "xcat-...-<uuid>" duplicates. This keeps stale connections from piling up and causing
    # keyfile-name collisions across cases.
    nmcli -t -f NAME connection show 2>/dev/null | grep -E "^xcat-.*${dev}" | while read -r c; do
        nmcli connection delete "$c" >/dev/null 2>&1
    done
    return 0
}

case "$1" in
    show)
        be=$(detect_backend); dev=$2
        case "$be" in
            nm) nm_show "$dev" ;;
            *)  file_show "$dev" ;;
        esac
        ;;
    del)
        be=$(detect_backend); shift
        for dev in "$@"; do
            case "$be" in
                nm)   nm_del "$dev" ;;
                suse) rm -f "$SUSEDIR/ifcfg-$dev" ;;
                rh)   rm -f "$RHDIR"/ifcfg-*"$dev"* ;;
                ubuntu) rm -f "$UBUDIR/$dev" "$UBUDIR/$dev":* ;;
            esac
        done
        ;;
    setip)
        be=$(detect_backend); dev=$2; newip=$3
        case "$be" in
            nm)   conn=$(nm_conn_for_dev "$dev")
                  pfx=$(nmcli -g ipv4.addresses connection show "$conn" 2>/dev/null | head -1 | sed 's,.*/,,')
                  [ -z "$pfx" ] && pfx=24
                  nmcli connection modify "$conn" ipv4.method manual ipv4.addresses "$newip/$pfx" >/dev/null 2>&1
                  nmcli connection up "$conn" >/dev/null 2>&1 ;;
            suse) sed -i "s,IPADDR=.*,IPADDR=$newip," "$SUSEDIR/ifcfg-$dev" ;;
            rh)   sed -i "s,IPADDR=.*,IPADDR=$newip," "$RHDIR"/ifcfg-*"$dev"* ;;
        esac
        ;;
    backup)
        be=$(detect_backend); rm -rf "$BACKUP"; mkdir -p "$BACKUP"
        case "$be" in
            nm)   cp -af "$NMDIR"/. "$BACKUP"/ 2>/dev/null ;;
            suse) cp -af "$SUSEDIR"/ifcfg-* "$BACKUP"/ 2>/dev/null ;;
            rh)   cp -af "$RHDIR" "$BACKUP"/ 2>/dev/null ;;
            ubuntu) cp -af "$UBUDIR"/. "$BACKUP"/ 2>/dev/null ;;
        esac
        ;;
    restore)
        be=$(detect_backend)
        case "$be" in
            nm)   rm -f "$NMDIR"/*.nmconnection 2>/dev/null; cp -af "$BACKUP"/. "$NMDIR"/ 2>/dev/null; chmod 600 "$NMDIR"/*.nmconnection 2>/dev/null; nmcli connection reload >/dev/null 2>&1 ;;
            suse) cp -af "$BACKUP"/ifcfg-* "$SUSEDIR"/ 2>/dev/null ;;
            rh)   cp -af "$BACKUP"/network-scripts/. "$RHDIR"/ 2>/dev/null; command -v nmcli >/dev/null 2>&1 && nmcli con reload >/dev/null 2>&1 ;;
            ubuntu) cp -af "$BACKUP"/. "$UBUDIR"/ 2>/dev/null ;;
        esac
        rm -rf "$BACKUP"
        ;;
    *)
        echo "usage: nic_cfg.sh {show|del <dev>|backup|restore}" >&2
        exit 2
        ;;
esac
