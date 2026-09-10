#!/bin/bash
#
# The xCAT side of the dhcptest wire cases.
#
# dhcptest itself never reads the xCAT database and never runs an xCAT
# command -- that is the whole point of it, and it is why the same .conf files
# can be pointed at any DHCP server. Everything that *does* know about xCAT
# lives here.
#
# It builds a self-contained provisioning network out of a veth pair, so the
# wire cases have something real to talk to on a management node that has no
# spare NIC -- a single-node CI runner, most of all. The server end carries
# the management address and is the only interface the DHCP daemon is told to
# listen on; the client end has no address at all, which is exactly the state
# a provisioning NIC is in when a machine boots on it.
#
# Usage:
#     dhcpfixture.sh check                   is this machine able to run the wire cases
#     dhcpfixture.sh setup                   build the network, the node and the config
#     dhcpfixture.sh run                     run dhcptest against it
#     dhcpfixture.sh backend <isc|kea>       switch backend and regenerate
#     dhcpfixture.sh alt-backend             name the other backend, if it is installed
#     dhcpfixture.sh delegate                hand the dynamic pool to another server
#     dhcpfixture.sh run-hierarchy           run dhcptest against the delegated network
#     dhcpfixture.sh teardown                put everything back
#
# `setup` records what it changed under $STATE and `teardown` restores it, so
# a case that fails half way still leaves the machine serving its own config.

set -u

IF_SRV=dhcptest0
IF_CLI=dhcptest1
NETOBJ=dhcptestnet
NET=10.99.0.0
MASK=255.255.255.0
PREFIX=24
SRV_IP=10.99.0.1
POOL=10.99.0.200-10.99.0.250
NODE=dhcptestcn
NODE_IP=10.99.0.11
NODE_MAC=52:54:00:dc:11:01
# Locally administered, so it belongs to no vendor and can never collide with
# a real machine on a real lab network.
UNKNOWN_MAC=02:00:dc:11:00:99

STATE=/tmp/dhcptest-fixture
DHCPTEST=/opt/xcat/share/xcat/tools/autotest/dhcptest
[ -d "$DHCPTEST" ] || DHCPTEST="$(cd "$(dirname "$0")/../../dhcptest" 2>/dev/null && pwd)"

say()  { echo "dhcpfixture: $*"; }
skip() { echo "dhcptest skipped: $*"; exit 1; }
die()  { echo "dhcpfixture: $*" >&2; exit 1; }

# The netboot method decides the boot file a reserved node is handed. grub2 is
# the one every backend renders the same way and without needing a loader to be
# present in the tftp directory first, so the wire expectation is exact rather
# than "something non-empty".
NETBOOT=grub2
node_loader() { echo "/boot/grub2/grub2-$NODE"; }

site_attr() {
    lsdef -t site clustersite -i "$1" -c 2>/dev/null \
        | grep "$1=" | awk -F= '{print $2}'
}

tftpdir() {
    local dir
    dir=$(site_attr tftpdir)
    echo "${dir:-/tftpboot}"
}

# What an unknown machine is told to boot, which is backend policy rather than
# protocol: Kea puts an architecture class on the subnet so every client on it
# is handed a loader, ISC leaves the boot file to the per-host blocks. An empty
# answer means "do not assert this here".
discovery_loader() {
    local backend
    backend=$(current_backend)
    [ "$backend" = kea ] || return 0
    if [ -f "$(tftpdir)/xcat/xnba.kpxe" ]; then
        echo "xcat/xnba.kpxe"
    else
        echo "pxelinux.0"
    fi
}

current_backend() {
    local value
    value=$(site_attr dhcpbackend)
    case "$value" in
        isc|kea) echo "$value" ;;
        *)       # `auto`, or unset: ask what is actually running.
                 if pgrep -x kea-dhcp4 >/dev/null 2>&1; then echo kea; else echo isc; fi ;;
    esac
}

service_of() {
    local backend=$1 unit
    case "$backend" in
        isc) for unit in isc-dhcp-server dhcpd; do
                 systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "^$unit" && { echo "$unit"; return 0; }
             done ;;
        kea) for unit in kea-dhcp4-server kea-dhcp4; do
                 systemctl list-unit-files "$unit.service" 2>/dev/null | grep -q "^$unit" && { echo "$unit"; return 0; }
             done ;;
    esac
    return 1
}

daemon_of() {
    case "$1" in
        isc) command -v dhcpd >/dev/null 2>&1 && echo dhcpd ;;
        kea) command -v kea-dhcp4 >/dev/null 2>&1 && echo kea-dhcp4 ;;
    esac
}

wait_for_daemon() {
    local name=$1 tries=0
    while [ $tries -lt 30 ]; do
        pgrep -x "$name" >/dev/null 2>&1 && return 0
        tries=$((tries + 1))
        sleep 1
    done
    return 1
}

do_check() {
    [ "$(id -u)" = 0 ] || skip "the wire cases send raw frames, which needs root"
    command -v ip >/dev/null 2>&1 || skip "iproute2 is not installed"
    command -v makedhcp >/dev/null 2>&1 || skip "makedhcp is not on PATH, so this is not a management node"
    [ -x "$DHCPTEST/src/dhcptest" ] || skip "dhcptest is not installed under $DHCPTEST"
    python3 -c "import scapy" 2>/dev/null || skip "python3-scapy is not installed"
    ip link add "${IF_SRV}probe" type veth peer name "${IF_CLI}probe" 2>/dev/null \
        || skip "this kernel has no veth support"
    ip link del "${IF_SRV}probe" 2>/dev/null
    say "environment is able to run the wire cases"
}

do_setup() {
    mkdir -p "$STATE" || die "cannot create $STATE"

    # Everything that gets changed is recorded first, so teardown is exact
    # rather than a guess at what the defaults used to be.
    tabdump site > "$STATE/site.csv" || die "cannot read the site table"
    for f in /etc/dhcp/dhcpd.conf /etc/dhcpd.conf /etc/kea/kea-dhcp4.conf; do
        [ -f "$f" ] && cp -f "$f" "$STATE/$(echo "$f" | tr / _)"
    done
    current_backend > "$STATE/backend"

    ip link show "$IF_SRV" >/dev/null 2>&1 && ip link del "$IF_SRV"
    ip link add "$IF_SRV" type veth peer name "$IF_CLI" || die "cannot create the veth pair"
    ip addr add "$SRV_IP/$PREFIX" dev "$IF_SRV" || die "cannot address $IF_SRV"
    ip link set "$IF_SRV" up || die "cannot bring up $IF_SRV"
    ip link set "$IF_CLI" up || die "cannot bring up $IF_CLI"
    echo done > "$STATE/veth"

    mkdef -f -t network -o "$NETOBJ" net="$NET" mask="$MASK" mgtifname="$IF_SRV" \
        gateway="$SRV_IP" tftpserver="$SRV_IP" nameservers="$SRV_IP" \
        dynamicrange="$POOL" domain=dhcptest.cluster \
        || die "cannot define the network $NETOBJ"
    echo done > "$STATE/network"

    mkdef -f -t node -o "$NODE" groups=dhcptest ip="$NODE_IP" mac="$NODE_MAC" \
        arch=x86_64 netboot="$NETBOOT" tftpserver="$SRV_IP" xcatmaster="$SRV_IP" \
        || die "cannot define the node $NODE"
    echo done > "$STATE/node"
    makehosts "$NODE" || die "cannot add $NODE to /etc/hosts"

    # The daemon is told to listen on the fixture interface and nothing else,
    # so a stray reply from the real provisioning network cannot be mistaken
    # for the answer under test.
    chdef -t site -o clustersite dhcpinterfaces="$IF_SRV" \
        || die "cannot set site.dhcpinterfaces"

    do_generate || return 1
    say "fixture is up on $IF_SRV/$IF_CLI, backend $(current_backend)"
}

do_generate() {
    local backend daemon
    backend=$(current_backend)
    daemon=$(daemon_of "$backend")
    [ -n "$daemon" ] || die "the $backend daemon is not installed"

    makedhcp -n || die "makedhcp -n failed"
    makedhcp "$NODE" || die "makedhcp $NODE failed"
    makedhcp -q "$NODE" || say "makedhcp -q reported no entry for $NODE"

    wait_for_daemon "$daemon" || die "$daemon is not running after makedhcp"
    say "$backend is serving: $daemon is running"
}

do_backend() {
    local want=$1 now unit daemon
    now=$(current_backend)
    [ "$want" = isc ] || [ "$want" = kea ] || die "unknown backend $want"
    daemon=$(daemon_of "$want")
    [ -n "$daemon" ] || die "the $want daemon is not installed on this machine"

    unit=$(service_of "$now")
    if [ -n "$unit" ]; then
        say "stopping $unit"
        systemctl stop "$unit" >/dev/null 2>&1
    fi

    chdef -t site -o clustersite dhcpbackend="$want" || die "cannot set site.dhcpbackend"
    do_generate || return 1
}

dhcptest_run() {
    ( cd "$DHCPTEST" && python3 src/dhcptest run -i "$IF_CLI" "$@" )
}

do_run() {
    local loader rc=0
    dhcptest_run \
        --set node_mac="$NODE_MAC" --set node_ip="$NODE_IP" \
        --set node_loader="$(node_loader)" --set pool="$POOL" \
        --set next_server="$SRV_IP" --set unknown_mac="$UNKNOWN_MAC" \
        conf/provision-vs-discovery.conf || rc=1

    loader=$(discovery_loader)
    if [ -n "$loader" ]; then
        dhcptest_run \
            --set unknown_mac="$UNKNOWN_MAC" --set pool="$POOL" \
            --set discovery_loader="$loader" \
            conf/discovery-bootfile.conf || rc=1
    else
        say "not asserting the discovery boot file: this backend leaves it to the per-host blocks"
    fi
    return $rc
}

# Hand the subnet's dynamic pool to another server, the way a management node
# does when a service node takes over a rack. Both backends drop a pool whose
# networks.dhcpserver is not this host, and the node's own next-server follows
# noderes.tftpserver, so the delegation is visible from the wire without a
# second machine existing.
DELEGATE_IP=10.99.0.5

do_delegate() {
    chdef -t network -o "$NETOBJ" dhcpserver="$DELEGATE_IP" \
        || die "cannot set networks.dhcpserver"
    chdef -t node -o "$NODE" tftpserver="$DELEGATE_IP" \
        || die "cannot point $NODE at the delegate"
    echo "$DELEGATE_IP" > "$STATE/delegate"
    do_generate || return 1
    say "the pool on $NET/$PREFIX now belongs to $DELEGATE_IP"
}

do_run_hierarchy() {
    ( cd "$DHCPTEST" && python3 src/dhcptest run -i "$IF_CLI" \
        --set node_mac="$NODE_MAC" --set node_ip="$NODE_IP" \
        --set delegate="$DELEGATE_IP" --set unknown_mac="$UNKNOWN_MAC" \
        conf/hierarchy-dhcpserver.conf )
}

do_teardown() {
    local unit
    [ -d "$STATE" ] || return 0

    [ -f "$STATE/node" ] && { makedhcp -d "$NODE" >/dev/null 2>&1; makehosts -d "$NODE" >/dev/null 2>&1; rmdef "$NODE" >/dev/null 2>&1; }
    [ -f "$STATE/network" ] && rmdef -t network -o "$NETOBJ" >/dev/null 2>&1
    [ -f "$STATE/veth" ] && ip link del "$IF_SRV" >/dev/null 2>&1

    # tabrestore replaces the table wholesale, which is what is wanted here:
    # dhcpinterfaces and dhcpbackend go back to exactly what they were, unset
    # included, rather than to a guess at the default.
    [ -f "$STATE/site.csv" ] && tabrestore "$STATE/site.csv" >/dev/null 2>&1

    for f in /etc/dhcp/dhcpd.conf /etc/dhcpd.conf /etc/kea/kea-dhcp4.conf; do
        local saved="$STATE/$(echo "$f" | tr / _)"
        [ -f "$saved" ] && cp -f "$saved" "$f"
    done

    if [ -f "$STATE/backend" ]; then
        unit=$(service_of "$(cat "$STATE/backend")")
        [ -n "$unit" ] && systemctl restart "$unit" >/dev/null 2>&1
    fi

    rm -rf "$STATE"
    say "fixture removed"
}

case "${1:-}" in
    check)       do_check ;;
    setup)       do_setup ;;
    generate)    do_generate ;;
    backend)     shift; do_backend "${1:-}" ;;
    alt-backend) if [ "$(current_backend)" = isc ]; then daemon_of kea >/dev/null && echo kea
                 else daemon_of isc >/dev/null && echo isc; fi ;;
    run)         do_run ;;
    delegate)      do_delegate ;;
    run-hierarchy) do_run_hierarchy ;;
    teardown)    do_teardown ;;
    *)           die "usage: $0 {check|setup|generate|backend <isc|kea>|alt-backend|run|delegate|run-hierarchy|teardown}" ;;
esac
