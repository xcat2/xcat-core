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
#     dhcpfixture.sh run-arch                one boot file per client architecture
#     dhcpfixture.sh run-netboot             one boot file per node netboot method
#     dhcpfixture.sh run-lease               the lease itself: handshake, renew, rebind, NAK
#     dhcpfixture.sh run-chainload           first stage versus chainloaded second stage
#     dhcpfixture.sh backends                name every backend installed here
#     dhcpfixture.sh backend-setup <b>       select a backend for a whole pass of the cases
#     dhcpfixture.sh backend-teardown <b>    put the backend selection back
#     dhcpfixture.sh delegate                hand the dynamic pool to another server
#     dhcpfixture.sh run-hierarchy           run dhcptest against the delegated network
#     dhcpfixture.sh run-adoption            discover a machine, define it, serve it its own address
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
MTU=1500
DOMAIN=dhcptest.cluster
NODE=dhcptestcn
NODE_IP=10.99.0.11
NODE_MAC=52:54:00:dc:11:01
# Locally administered, so it belongs to no vendor and can never collide with
# a real machine on a real lab network.
UNKNOWN_MAC=02:00:dc:11:00:99

# The machine that gets discovered and then adopted while the server keeps
# running. Defined by `run-adoption`, not by `setup`, because the whole point
# is what changes between the two DISCOVERs.
ADOPT_NODE=dhcptestcn2
ADOPT_IP=10.99.0.12
ADOPT_MAC=02:00:dc:11:00:aa

# An address on a network this server has never heard of, for the DHCPNAK case.
# 192.0.2.0/24 is TEST-NET-1 and is not routable anywhere.
FOREIGN_IP=192.0.2.77

STATE=/tmp/dhcptest-fixture
# What backend-setup saved, so backend-teardown can put it back. Separate from
# $STATE because it outlives every case in the pass: $STATE belongs to one case
# and is removed by that case's teardown.
BSTATE=/tmp/dhcptest-backend
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

# The lease time both backends write when site.dhcplease is unset.
lease_time() {
    local value
    value=$(site_attr dhcplease)
    echo "${value:-43200}"
}

# What an unknown machine is told to boot.
#
# A machine being discovered has no reservation by definition, so the answer can
# only come from the subnet -- and it has to come, or the machine has no way to
# reach the state where someone could define it. The specification says so for
# both backends (S-56), so this no longer asks which one is running.
discovery_loader() {
    arch_loader bios
}

# What a machine of a given client architecture, with no reservation, must be
# told to boot: one answer per architecture, the same one for every backend.
#
# This used to branch on the backend, which made the drift it exists to catch
# impossible to see -- whatever each backend did was what the test expected of
# it, so the two could disagree for ever and the case would still pass. A node
# does not choose its management node's DHCP backend, so an architecture that
# boots under one and hangs under the other is a bug in whichever one is wrong,
# and a wire test has to be able to say so.
#
# The backends do read one thing off this machine before deciding: whether the
# loader is already unpacked under tftpdir. setup puts every loader they key on
# in place (see provide_loaders), so both are configured from the same inputs
# and any difference left in the reply is a difference in behaviour.
arch_loader() {
    case "$1" in
        bios)        echo "xcat/xnba.kpxe" ;;
        uefi)        echo "xcat/xnba.efi" ;;
        aarch64)     echo "boot/grub2/grub2.aarch64" ;;
        riscv64)     echo "boot/grub2/grub2.riscv64" ;;
        ia64)        echo "elilo.efi" ;;
        ppc64)       echo "/boot/grub2/grub2.ppc" ;;
        # No option 93 and no vendor class anyone recognises. The reply still
        # has to name something, or the client cannot tell it was served.
        fallback)    echo "/yaboot" ;;
    esac
}

# The three subnet answers that are a URL or a conf-file rather than a loader.
# All of them are built out of the network the fixture defined, which is why
# they are here and not in arch_loader.
NETID="${NET}_${PREFIX}"
opal_conf()  { echo "http://$SRV_IP/tftpboot/pxelinux.cfg/p/$NETID"; }
s390x_conf() { echo "s390x/$NETID"; }
onie_url()   { echo "http://$SRV_IP/install/onie/onie-installer"; }

# The second stage of a chained xNBA boot, in its two forms. A client the
# server holds no reservation for can only be answered per network; one it does
# know is answered per node, and that is the whole point of the second stage --
# two machines chainloading at the same instant must not run the same script.
xnba_net_url()  { echo "http://$SRV_IP/tftpboot/xcat/xnba/nets/$NETID"; }
xnba_node_url() { echo "http://$SRV_IP/tftpboot/xcat/xnba/nodes/$1"; }

# The loaders whose presence changes what a backend answers, relative to tftpdir.
#
#   xcat/xnba.kpxe             Kea names it if it is there and falls back to
#                              pxelinux.0 if it is not; ISC names it either way.
#   xcat/xnba.efi              Kea emits no UEFI x64 class at all without it;
#                              ISC names it either way.
#   boot/grub2/grub2.riscv64   gates Kea's riscv64 HTTP boot class; ISC emits
#                              the HTTP branch either way.
#
# grub2.aarch64 is not listed: neither backend keys on it.
GATING_LOADERS="xcat/xnba.kpxe xcat/xnba.efi boot/grub2/grub2.riscv64"

# Put an empty file where a gating loader is missing, and record it so teardown
# takes back exactly what was added and nothing else.
#
# An empty file is enough because nothing here fetches one: dhcptest asserts the
# name in the BOOTP file field and never opens a TFTP session. What matters is
# that the two backends are asked the same question -- otherwise a parity
# failure would only mean this machine had not unpacked a loader, which is a
# fact about the runner and not about xCAT.
provide_loaders() {
    local rel path tftp
    tftp=$(tftpdir)
    : > "$STATE/loaders" || die "cannot record which loaders were placed"

    for rel in $GATING_LOADERS; do
        path="$tftp/$rel"
        [ -f "$path" ] && continue
        mkdir -p "$(dirname "$path")" || die "cannot create $(dirname "$path")"
        : > "$path" || die "cannot place a loader at $path"
        echo "$path" >> "$STATE/loaders"
        say "placed an empty $rel so both backends are configured from the same inputs"
    done
}

withdraw_loaders() {
    local path
    [ -f "$STATE/loaders" ] || return 0
    while read -r path; do
        [ -n "$path" ] && rm -f "$path"
    done < "$STATE/loaders"
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
    # -f rather than -x: the fixture runs it as `python3 src/dhcptest`, so the
    # execute bit is only needed by whoever calls it directly. Testing -x here
    # made every wire case skip -- and pass -- on Debian, where dh_install keeps
    # the source mode and the RPM's chmod has no counterpart.
    [ -f "$DHCPTEST/src/dhcptest" ] || skip "dhcptest is not installed under $DHCPTEST"
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

    # Every attribute set here is one option the reply has to carry. An
    # installer that gets an address and no gateway, resolver or MTU fails much
    # later and much less obviously than one that gets no address at all, which
    # is why they are configured and asserted rather than left at the default.
    mkdef -f -t network -o "$NETOBJ" net="$NET" mask="$MASK" mgtifname="$IF_SRV" \
        gateway="$SRV_IP" tftpserver="$SRV_IP" nameservers="$SRV_IP" \
        dynamicrange="$POOL" domain="$DOMAIN" mtu="$MTU" \
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

    # Before the config is generated: both backends read tftpdir while deciding
    # which boot classes to write, so the loaders have to be in place first.
    provide_loaders

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

installed_backends() {
    local backend out=
    for backend in isc kea; do
        daemon_of "$backend" >/dev/null && out="$out $backend"
    done
    echo $out
}

# Select a DHCP backend for a whole pass of the wire cases.
#
# Which backend a cluster runs is an implementation default -- Backend.pm picks
# kea on Ubuntu >= 22.04 and EL >= 10 and isc below, and `auto` flips the moment
# kea-dhcp4 appears -- so a booting machine must see the same answers either
# way. Testing whichever backend happened to be configured proves half of that
# and hides every drift between the two.
#
# The choice is made once per pass and not once per case: the caller runs every
# case against isc, then every case again against kea. Switching inside each
# case would reconfigure and restart the daemon between every one of them, and a
# failure in the log would not say which backend it belonged to without counting
# lines.
#
# Only site.dhcpbackend is set here. Each case's own setup saves the site table
# and its teardown restores it, so the selection survives the whole pass, and
# the config itself is generated per case by makedhcp as before.
do_backend_setup() {
    local want=${1:-} unit other
    [ "$want" = isc ] || [ "$want" = kea ] || die "usage: $0 backend-setup <isc|kea>"
    daemon_of "$want" >/dev/null || die "the $want daemon is not installed on this machine"

    mkdir -p "$BSTATE" || die "cannot create $BSTATE"
    tabdump site > "$BSTATE/site.csv" || die "cannot read the site table"
    current_backend > "$BSTATE/backend"

    # Two daemons on one wire both answer the same DISCOVER, and the case would
    # be asserting on whichever won the race.
    [ "$want" = isc ] && other=kea || other=isc
    unit=$(service_of "$other")
    [ -n "$unit" ] && { say "stopping $unit"; systemctl stop "$unit" >/dev/null 2>&1; }

    chdef -t site -o clustersite dhcpbackend="$want" || die "cannot set site.dhcpbackend"
    say "===== the wire cases now run against $want ====="
}

# Undo backend-setup: stop what the pass was serving with and put the site table
# back exactly as it was, unset included, rather than to a guess at the default.
do_backend_teardown() {
    local want=${1:-} unit was
    [ -d "$BSTATE" ] || { say "no backend pass to tear down"; return 0; }

    unit=$(service_of "$want")
    [ -n "$unit" ] && systemctl stop "$unit" >/dev/null 2>&1

    tabrestore "$BSTATE/site.csv" >/dev/null 2>&1
    was=$(cat "$BSTATE/backend" 2>/dev/null)
    unit=$(service_of "$was")
    [ -n "$unit" ] && systemctl restart "$unit" >/dev/null 2>&1

    rm -rf "$BSTATE"
    say "===== the $want pass is over; $was is serving again ====="
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
        --set gateway="$SRV_IP" --set nameservers="$SRV_IP" \
        --set domain="$DOMAIN" --set mtu="$MTU" --set lease="$(lease_time)" \
        conf/provision-vs-discovery.conf || rc=1

    # A reservation is a reservation whichever way the node was reached, so the
    # same node has to answer static-vs-dynamic.conf as well: it asks the same
    # question from the other end, starting from the pool.
    dhcptest_run \
        --set reserved_mac="$NODE_MAC" --set reserved_ip="$NODE_IP" \
        --set unreserved_mac="$UNKNOWN_MAC" --set pool="$POOL" \
        conf/static-vs-dynamic.conf || rc=1

    loader=$(discovery_loader)
    dhcptest_run \
        --set unknown_mac="$UNKNOWN_MAC" --set pool="$POOL" \
        --set discovery_loader="$loader" \
        conf/discovery-bootfile.conf || rc=1
    return $rc
}

# One DISCOVER per client architecture, asserting the loader each one is handed.
#
# This is the part of xCAT's DHCP behaviour with the most branches and, until
# now, the least wire coverage: a single grub2 assertion for one architecture.
# Every architecture is asserted under every backend, with the same expected
# loader for both -- see arch_loader for why nothing is skipped by backend.
# The whole file runs in one invocation. It used to run one scenario at a time
# with every other loader variable set to a placeholder, because only one of
# them had a real value; now that each architecture has an answer the
# specification states for both backends, there is nothing left to hide.
#
# The riscv64 HTTP scenario asserts a prefix and a substring rather than the
# whole URL, so it reads the same riscv64_loader path the TFTP scenario does.
do_run_arch() {
    dhcptest_run --set tftp="$SRV_IP" \
        --set bios_loader="$(arch_loader bios)" \
        --set uefi_loader="$(arch_loader uefi)" \
        --set aarch64_loader="$(arch_loader aarch64)" \
        --set riscv64_loader="$(arch_loader riscv64)" \
        --set ia64_loader="$(arch_loader ia64)" \
        --set ppc64_loader="$(arch_loader ppc64)" \
        --set fallback_loader="$(arch_loader fallback)" \
        --set opal_conf="$(opal_conf)" \
        --set s390x_conf="$(s390x_conf)" \
        --set onie_url="$(onie_url)" \
        conf/pxe-arch-matrix.conf
}

# One node per netboot method.
#
# The method is an attribute of the node, so the loader can only come from what
# the operator wrote against it. A subnet-wide boot class sees the client
# architecture and nothing else, so a backend that leans on one answers a nimol
# node with an x86 loader and the machine does not install.
#
# name:method:ip:mac -- the addresses sit above the node the rest of the
# fixture defines and below the dynamic pool, so nothing here collides.
NETBOOT_NODES="
dhcptestnbxnba:xnba:10.99.0.21:02:00:dc:11:00:21
dhcptestnbpxe:pxe:10.99.0.22:02:00:dc:11:00:22
dhcptestnbgrub:grub2:10.99.0.23:02:00:dc:11:00:23
dhcptestnbybt:yaboot:10.99.0.24:02:00:dc:11:00:24
dhcptestnbnml:nimol:10.99.0.25:02:00:dc:11:00:25
dhcptestnbptb:petitboot:10.99.0.26:02:00:dc:11:00:26
"

# The node carrying the second NIC the operator marked *NOIP*: a port that must
# never boot, on a machine that provisions through another one. It is a mac
# table entry rather than a node of its own, which is the only way xCAT can
# express it.
NOIP_NODE=dhcptestnbnoip
NOIP_NODE_IP=10.99.0.27
NOIP_NODE_MAC=02:00:dc:11:00:27
NOIP_MAC=02:00:dc:11:00:07

netboot_field() { echo "$1" | cut -d: -f"$2"; }
netboot_mac()   { echo "$1" | cut -d: -f4-9; }

# What each method's node has to be handed. Same expectation for both backends:
# the operator wrote the method, not the backend.
netboot_loader() {
    local method=$1 node=$2
    case "$method" in
        xnba)      arch_loader bios ;;
        pxe)       echo "pxelinux.0" ;;
        grub2)     echo "/boot/grub2/grub2-$node" ;;
        yaboot)    echo "/yb/node/yaboot-$node" ;;
        nimol)     echo "/vios/nodes/$node" ;;
        petitboot) echo "http://$SRV_IP/tftpboot/petitboot/$node" ;;
    esac
}

netboot_define() {
    local entry name method ip mac
    : > "$STATE/netboot" || die "cannot record the netboot nodes"

    for entry in $NETBOOT_NODES; do
        name=$(netboot_field "$entry" 1)
        method=$(netboot_field "$entry" 2)
        ip=$(netboot_field "$entry" 3)
        mac=$(netboot_mac "$entry")

        mkdef -f -t node -o "$name" groups=dhcptest ip="$ip" mac="$mac" \
            arch=x86_64 netboot="$method" tftpserver="$SRV_IP" xcatmaster="$SRV_IP" \
            || die "cannot define $name"
        echo "$name" >> "$STATE/netboot"
        makehosts "$name" || die "cannot add $name to /etc/hosts"
        makedhcp "$name" || die "makedhcp $name failed"
    done

    # Two entries on one node: the port that provisions, and the port that must
    # not. Only the second is asserted, but it cannot exist without the first.
    mkdef -f -t node -o "$NOIP_NODE" groups=dhcptest ip="$NOIP_NODE_IP" \
        mac="$NOIP_NODE_MAC!$NOIP_NODE|$NOIP_MAC!*NOIP*" \
        arch=x86_64 netboot=grub2 tftpserver="$SRV_IP" xcatmaster="$SRV_IP" \
        || die "cannot define $NOIP_NODE"
    echo "$NOIP_NODE" >> "$STATE/netboot"
    makehosts "$NOIP_NODE" || die "cannot add $NOIP_NODE to /etc/hosts"
    makedhcp "$NOIP_NODE" || die "makedhcp $NOIP_NODE failed"
}

netboot_undefine() {
    local name
    [ -f "$STATE/netboot" ] || return 0
    while read -r name; do
        [ -n "$name" ] || continue
        makedhcp -d "$name" >/dev/null 2>&1
        makehosts -d "$name" >/dev/null 2>&1
        rmdef "$name" >/dev/null 2>&1
    done < "$STATE/netboot"
}

do_run_netboot() {
    local entry name method ip mac
    netboot_define

    for entry in $NETBOOT_NODES; do
        name=$(netboot_field "$entry" 1)
        method=$(netboot_field "$entry" 2)
        ip=$(netboot_field "$entry" 3)
        mac=$(netboot_mac "$entry")
        eval "${method}_node=\$name; ${method}_ip=\$ip; ${method}_mac=\$mac"
    done

    dhcptest_run \
        --set xnba_mac="$xnba_mac"   --set xnba_ip="$xnba_ip" \
        --set xnba_node="$xnba_node" --set xnba_loader="$(netboot_loader xnba "$xnba_node")" \
        --set xnba_stage2="$(xnba_node_url "$xnba_node")" \
        --set pxe_mac="$pxe_mac"     --set pxe_ip="$pxe_ip" \
        --set pxe_loader="$(netboot_loader pxe "$pxe_node")" \
        --set scalemp_loader="vsmp/pxelinux.0" \
        --set grub2_mac="$grub2_mac" --set grub2_ip="$grub2_ip" \
        --set grub2_loader="$(netboot_loader grub2 "$grub2_node")" \
        --set yaboot_mac="$yaboot_mac" \
        --set yaboot_loader="$(netboot_loader yaboot "$yaboot_node")" \
        --set nimol_mac="$nimol_mac" \
        --set nimol_loader="$(netboot_loader nimol "$nimol_node")" \
        --set petitboot_mac="$petitboot_mac" \
        --set petitboot_conf="$(netboot_loader petitboot "$petitboot_node")" \
        --set noip_mac="$NOIP_MAC" \
        conf/netboot-methods.conf
}

# The two halves of a chained network boot.
#
# Firmware PXE sends no user class and must be handed a loader binary. The
# loader that firmware just ran announces itself with user class xNBA and must
# be handed something else -- the per-network script URL -- or it chainloads
# itself forever, and the machine sits at a boot prompt that never advances.
#
# Both encodings of option 77 are sent: the bare string, and the length-prefixed
# form RFC 3004 specifies. The same firmware sends either depending on how it
# was built, so a server that recognises only one of them boots half the fleet
# and loops the other half. Both backends render this branch on the subnet, so
# no node has to be defined with netboot=xnba for it.
do_run_chainload() {
    dhcptest_run --set user_class=xNBA --set stage1_loader="$(arch_loader bios)" \
        --set stage1_uefi_loader="$(arch_loader uefi)" \
        --set stage2_loader="$(xnba_net_url)" \
        conf/ipxe-userclass.conf
}

# The lease itself, rather than what is booted with it: the four-way handshake,
# renewal, rebinding, and the refusal of an address this network cannot give.
#
# The DHCPNAK matters as much as the ACK. A node moved between racks comes back
# asking for the address it still holds; a server that stays silent leaves it
# retrying forever, which on a provisioning network is indistinguishable from a
# node that will not boot.
do_run_lease() {
    local rc=0
    dhcptest_run --set net="$NET/$PREFIX" conf/full-lease.conf   || rc=1
    dhcptest_run --set net="$NET/$PREFIX" conf/renew-rebind.conf || rc=1
    dhcptest_run --set foreign_ip="$FOREIGN_IP" conf/nak-foreign-address.conf || rc=1
    return $rc
}

# Discovery, end to end: a machine nobody has heard of takes a pool address,
# gets defined as a node, and from the next DISCOVER on is served its own
# address instead -- with the daemon never restarted in between.
#
# That last part is the assertion with teeth. xCAT injects ISC reservations
# into the leases file over OMAPI precisely so a node being adopted does not
# interrupt every other node still being discovered; a regression to rewriting
# dhcpd.conf and bouncing the daemon would still pass every static test in this
# tree. So the daemon's pid is taken before and after and has to match.
do_run_adoption() {
    local rc=0 daemon before after
    daemon=$(daemon_of "$(current_backend)")
    [ -n "$daemon" ] || die "no DHCP daemon is installed"

    dhcptest_run -s machine-is-unknown \
        --set adopt_mac="$ADOPT_MAC" --set adopt_ip="$ADOPT_IP" --set pool="$POOL" \
        conf/discovery-adoption.conf || rc=1

    before=$(pgrep -x "$daemon" | head -1)
    [ -n "$before" ] || die "$daemon is not running before the node is adopted"

    mkdef -f -t node -o "$ADOPT_NODE" groups=dhcptest ip="$ADOPT_IP" mac="$ADOPT_MAC" \
        arch=x86_64 netboot="$NETBOOT" tftpserver="$SRV_IP" xcatmaster="$SRV_IP" \
        || die "cannot define the node $ADOPT_NODE"
    echo done > "$STATE/adopt"
    makehosts "$ADOPT_NODE" || die "cannot add $ADOPT_NODE to /etc/hosts"
    makedhcp "$ADOPT_NODE" || die "makedhcp $ADOPT_NODE failed"

    after=$(pgrep -x "$daemon" | head -1)
    if [ "$before" != "$after" ]; then
        say "FAILED: $daemon was restarted to adopt one node (pid $before -> $after)"
        rc=1
    else
        say "$daemon kept running while $ADOPT_NODE was adopted (pid $before)"
    fi

    dhcptest_run -s machine-has-been-adopted \
        --set adopt_mac="$ADOPT_MAC" --set adopt_ip="$ADOPT_IP" --set pool="$POOL" \
        conf/discovery-adoption.conf || rc=1

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
        --set node_loader="$(node_loader)" \
        --set delegate="$DELEGATE_IP" --set unknown_mac="$UNKNOWN_MAC" \
        conf/hierarchy-dhcpserver.conf )
}

do_teardown() {
    local unit
    [ -d "$STATE" ] || return 0

    [ -f "$STATE/node" ] && { makedhcp -d "$NODE" >/dev/null 2>&1; makehosts -d "$NODE" >/dev/null 2>&1; rmdef "$NODE" >/dev/null 2>&1; }
    [ -f "$STATE/adopt" ] && { makedhcp -d "$ADOPT_NODE" >/dev/null 2>&1; makehosts -d "$ADOPT_NODE" >/dev/null 2>&1; rmdef "$ADOPT_NODE" >/dev/null 2>&1; }
    netboot_undefine
    [ -f "$STATE/network" ] && rmdef -t network -o "$NETOBJ" >/dev/null 2>&1
    [ -f "$STATE/veth" ] && ip link del "$IF_SRV" >/dev/null 2>&1
    withdraw_loaders

    # tabrestore replaces the table wholesale, which is what is wanted here:
    # dhcpinterfaces and dhcpbackend go back to exactly what they were, unset
    # included, rather than to a guess at the default.
    [ -f "$STATE/site.csv" ] && tabrestore "$STATE/site.csv" >/dev/null 2>&1

    for f in /etc/dhcp/dhcpd.conf /etc/dhcpd.conf /etc/kea/kea-dhcp4.conf; do
        local saved="$STATE/$(echo "$f" | tr / _)"
        [ -f "$saved" ] && cp -f "$saved" "$f"
    done

    if [ -f "$STATE/backend" ]; then
        local was other
        was=$(cat "$STATE/backend")
        # Two servers on one network answer the same DISCOVER, so stop the other
        # one before restarting the backend this case was serving with.
        [ "$was" = isc ] && other=kea || other=isc
        unit=$(service_of "$other")
        [ -n "$unit" ] && systemctl stop "$unit" >/dev/null 2>&1
        unit=$(service_of "$was")
        [ -n "$unit" ] && systemctl restart "$unit" >/dev/null 2>&1
    fi

    rm -rf "$STATE"
    say "fixture removed"
}

dispatch() {
    case "${1:-}" in
    check)       do_check ;;
    setup)       do_setup ;;
    generate)    do_generate ;;
    backends)    installed_backends ;;
    backend-setup)    shift; do_backend_setup "${1:-}" ;;
    backend-teardown) shift; do_backend_teardown "${1:-}" ;;
    run)         do_run ;;
    run-arch)      do_run_arch ;;
    run-netboot)   do_run_netboot ;;
    run-lease)     do_run_lease ;;
    run-chainload) do_run_chainload ;;
    delegate)      do_delegate ;;
    run-hierarchy) do_run_hierarchy ;;
    run-adoption)  do_run_adoption ;;
    teardown)    do_teardown ;;
    *)           die "usage: $0 {check|setup|generate|backends|backend-setup <isc|kea>|backend-teardown <isc|kea>|run|run-arch|run-netboot|run-lease|run-chainload|delegate|run-hierarchy|run-adoption|teardown}" ;;
    esac
}

dispatch "$@"
