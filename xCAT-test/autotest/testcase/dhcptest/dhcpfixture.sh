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

# What an unknown machine is told to boot, which is backend policy rather than
# protocol: Kea puts an architecture class on the subnet so every client on it
# is handed a loader, ISC leaves the boot file to the per-host blocks. An empty
# answer means "do not assert this here".
discovery_loader() {
    [ "$(current_backend)" = kea ] || return 0
    arch_loader bios
}

# What a machine of a given client architecture, with no reservation, is told
# to boot. This is the one place in the fixture that has to know each backend's
# policy, because the two genuinely differ in what they will answer at all:
#
#   x86 BIOS      ISC always names xnba.kpxe; Kea names it only if it is there
#                 and falls back to pxelinux.0, since Kea has no equivalent of
#                 dhcpd's "hand it out and let TFTP fail".
#   x86-64 UEFI   ISC always names xnba.efi; Kea emits no UEFI class at all
#                 unless the loader exists, so there is nothing to assert.
#   aarch64       both, unconditionally.
#   riscv64 TFTP  both, unconditionally.
#   riscv64 HTTP  ISC always; Kea only if the loader exists.
#
# An empty answer means "this backend will not answer for this architecture on
# this machine, so do not assert anything". Skipping is the honest outcome:
# asserting a loader that was never configured tests the fixture, not xCAT.
arch_loader() {
    local arch=$1 backend tftp
    backend=$(current_backend)
    tftp=$(tftpdir)

    case "$arch" in
        bios)
            if [ "$backend" = isc ] || [ -f "$tftp/xcat/xnba.kpxe" ]; then
                echo "xcat/xnba.kpxe"
            else
                echo "pxelinux.0"
            fi ;;
        uefi)
            if [ "$backend" = isc ] || [ -f "$tftp/xcat/xnba.efi" ]; then
                echo "xcat/xnba.efi"
            fi ;;
        aarch64)     echo "boot/grub2/grub2.aarch64" ;;
        riscv64)     echo "boot/grub2/grub2.riscv64" ;;
        riscv64http)
            if [ "$backend" = isc ] || [ -f "$tftp/boot/grub2/grub2.riscv64" ]; then
                echo "http://$SRV_IP/tftpboot/boot/grub2/grub2.riscv64"
            fi ;;
    esac
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

# One DISCOVER per client architecture, asserting the loader each one is handed.
#
# This is the part of xCAT's DHCP behaviour with the most branches and, until
# now, the least wire coverage: a single grub2 assertion for one architecture.
# The architectures a backend will not answer for on this machine are skipped
# by name, so the report says which ones ran rather than quietly passing.
do_run_arch() {
    local rc=0 entry arch scenario variable loader

    # arch, the scenario that exercises it, and the variable that scenario
    # reads its expected loader from. Every other loader variable is set to a
    # value nothing matches, since the .conf declares all of them but only one
    # scenario is run at a time.
    for entry in \
        "bios:pxe-bios-x86:bios_loader" \
        "uefi:pxe-uefi-x64:uefi_loader" \
        "aarch64:pxe-aarch64:aarch64_loader" \
        "riscv64:pxe-riscv64-tftp:riscv64_loader" \
        "riscv64http:httpboot-riscv64:riscv64_loader"
    do
        arch=${entry%%:*}
        scenario=${entry#*:}; scenario=${scenario%%:*}
        variable=${entry##*:}

        loader=$(arch_loader "$arch")
        if [ -z "$loader" ]; then
            say "skipping the $arch boot file: $(current_backend) does not serve it on this machine"
            continue
        fi

        # The HTTP scenario asserts a prefix and a substring rather than the
        # whole URL, so what it wants is the path inside it.
        [ "$arch" = riscv64http ] && loader=boot/grub2/grub2.riscv64

        dhcptest_run -s "$scenario" --set tftp="$SRV_IP" \
            --set bios_loader=- --set uefi_loader=- \
            --set aarch64_loader=- --set riscv64_loader=- \
            --set "$variable=$loader" \
            conf/pxe-arch-matrix.conf || rc=1
    done
    return $rc
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
    local stage1
    stage1=$(arch_loader bios)
    [ -n "$stage1" ] || { say "skipping the chainload cases: no BIOS loader is served here"; return 0; }

    dhcptest_run --set user_class=xNBA --set stage1_loader="$stage1" \
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
        --set delegate="$DELEGATE_IP" --set unknown_mac="$UNKNOWN_MAC" \
        conf/hierarchy-dhcpserver.conf )
}

do_teardown() {
    local unit
    [ -d "$STATE" ] || return 0

    [ -f "$STATE/node" ] && { makedhcp -d "$NODE" >/dev/null 2>&1; makehosts -d "$NODE" >/dev/null 2>&1; rmdef "$NODE" >/dev/null 2>&1; }
    [ -f "$STATE/adopt" ] && { makedhcp -d "$ADOPT_NODE" >/dev/null 2>&1; makehosts -d "$ADOPT_NODE" >/dev/null 2>&1; rmdef "$ADOPT_NODE" >/dev/null 2>&1; }
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
    run-lease)     do_run_lease ;;
    run-chainload) do_run_chainload ;;
    delegate)      do_delegate ;;
    run-hierarchy) do_run_hierarchy ;;
    run-adoption)  do_run_adoption ;;
    teardown)    do_teardown ;;
    *)           die "usage: $0 {check|setup|generate|backends|backend-setup <isc|kea>|backend-teardown <isc|kea>|run|run-arch|run-lease|run-chainload|delegate|run-hierarchy|run-adoption|teardown}" ;;
    esac
}

dispatch "$@"
