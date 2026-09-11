#!/bin/bash
#
# The xCAT side of the provtest wire cases: provtest knows nothing about xCAT,
# so everything that does lives here. It builds a provisioning network out of a
# veth pair, the client end holding the node's address, because xcatd names a
# client by the reverse lookup of the address a request arrived from.
#
# Usage:
#     provfixture.sh check              can this machine run the wire cases
#     provfixture.sh setup              build the network, nodes, tree, config
#     provfixture.sh run-dns            stage 1: records a node and server need
#     provfixture.sh run-tftp           stage 3: one netboot method per file
#     provfixture.sh run-http           stage 4: the aliases and the node's URLs
#     provfixture.sh run-genesis        stage 5: per-network discovery artefacts
#     provfixture.sh run-discovery      stages 6-7: flow control, then findme
#     provfixture.sh run-xcatd          stages 9-12: destiny, policy, creds, postscript
#     provfixture.sh run-monitor        stage 13: the install monitor on 3002
#     provfixture.sh run-ordering       failing at one place: P-72, P-74, P-75
#     provfixture.sh run-dns-removal    what a withdrawn node stops resolving to
#     provfixture.sh generate           re-run nodeset and makedns
#     provfixture.sh teardown           put everything back
#
# setup records what it changed under $STATE; teardown puts it back.

set -u

IF_SRV=provtest0
IF_CLI=provtest1
# The namespace the client end lives in; do_setup says why the node needs a
# network stack of its own.
NETNS=provtestns
NETOBJ=provtestnet
NET=10.99.1.0
MASK=255.255.255.0
PREFIX=24
# What mknb names the xnba per-network scripts: network and prefix, joined by
# an underscore because a slash cannot be a file name.
NET_FILE=10.99.1.0_24
SRV_IP=10.99.1.1
DOMAIN=provtest.cluster

# site.master is an address; P-07 is about a name, so the master gets a node
# definition of its own and DNS gets an A record out of it.
MASTER_NODE=provtestmn

# The node every stage runs as; the client end holds this address alone.
# netboot is grub2-http because P-39 reads the port out of the HTTP entry.
NODE=provtestcn
NODE_IP=10.99.1.11
NODE_MAC=52:54:00:dc:11:01
NODE_NETBOOT=grub2-http
ALIAS=provtestcn-eth0

# One node per netboot method: a node has one method at a time, so reconfiguring
# one between files would assert against a machine that no longer exists.
PXE_NODE=provtestpx
PXE_IP=10.99.1.12
PXE_MAC=02:00:dc:11:01:12
BOOT_NODE=provtestbn
BOOT_IP=10.99.1.13
BOOT_MAC=02:00:dc:11:01:13
XNBA_NODE=provtestxn
XNBA_IP=10.99.1.14
XNBA_MAC=02:00:dc:11:01:14
PTB_NODE=provtestpb
PTB_IP=10.99.1.15
PTB_MAC=02:00:dc:11:01:15

# An address no node holds and no PTR names. Every "unknown client" scenario is
# this address and nothing else.
UNKNOWN_IP=10.99.1.201

# On-link and unassigned, so TLS to it times out rather than being refused --
# what a node whose master is dead actually experiences.
UNREACHABLE_IP=10.99.1.250

# A network xCAT neither manages nor is attached to, for P-43. Routed to through
# the node, so it never becomes one of the management node's own.
FOREIGN_NET=10.98.1.0
FOREIGN_IP=10.98.1.11

MISSING=nosuchnode
# A name in no local zone. run-dns leaves the scenario out when no forwarder
# works, rather than reporting a missing internet connection as a fault.
FORWARDED=example.com

XCATPORT=3001
MONITORPORT=3002

# The web port the cluster is told to use, if the fixture can arrange one.
# grub2 writes the port into a node's config only when site.httpport is not 80
# (grub2.pm:267), so the fixture moves it and adds a Listen line, putting both
# back if the server refuses -- in which case the HTTP stage asserts the
# default-port half of P-39. Empty means the port was left alone.
HTTPPORT=

# The install tree the nodes point at. The version cannot exist, so no real tree
# can be found or destroyed.
OSVERS=rhels9.99
OSIMAGE=provtest-install
PTB_OSIMAGE=provtest-install-ppc64
NODE_ARCH=x86_64
PTB_ARCH=ppc64le

# What nodeset is told to do, twice. `shell` not `boot`: only a genesis destiny
# writes destiny= on the kernel command line, which is what P-75 asserts.
DESTINY=install
SECOND_DESTINY=shell

STATE=/tmp/provtest-fixture
PROVTEST=/opt/xcat/share/xcat/tools/autotest/provtest
[ -d "$PROVTEST" ] || PROVTEST="$(cd "$(dirname "$0")/../../../provtest" 2>/dev/null && pwd)"

say()  { echo "provfixture: $*"; }
skip() { echo "provtest skipped: $*"; exit 1; }
die()  { echo "provfixture: $*" >&2; exit 1; }

# A stage this machine cannot run: says what is missing and passes.
stage_skip() { echo "provtest stage skipped: $*"; return 0; }

site_attr() {
    lsdef -t site clustersite -i "$1" -c 2>/dev/null \
        | grep "$1=" | awk -F= '{print $2}'
}

# Asked once each: every one costs an lsdef, and nothing here changes them.
tftpdir() {
    [ -n "${TFTPDIR:-}" ] || TFTPDIR=$(site_attr tftpdir)
    echo "${TFTPDIR:-/tftpboot}"
}

installdir() {
    [ -n "${INSTALLDIR:-}" ] || INSTALLDIR=$(site_attr installdir)
    echo "${INSTALLDIR:-/install}"
}

# Not cached, unlike the two above: setup moves site.httpport when it can, so
# the answer changes within a single run.
httpport() {
    local port
    port=$(site_attr httpport)
    echo "${port:-80}"
}

# Whether the web server on a port serves what xCAT tells a node to fetch,
# rather than merely answering: a stock server in front of the httpd carrying
# xcat.conf replies 404 to every path a node is given, which reads as a broken
# boot configuration. Asks for the two aliased directories by their own paths;
# anything but 404 means the alias is there, 403 included.
http_serves_xcat() {
    local port=$1 path code
    for path in "$(tftpdir)" "$(installdir)"; do
        code=$(curl -s -m 5 -o /dev/null -w '%{http_code}' \
                    "http://127.0.0.1:$port$path/" 2>/dev/null)
        # 000 is curl's own: nothing answered at all.
        case "$code" in 404|000|'') return 1 ;; esac
    done
    return 0
}

# Where a web server keeps the configuration fragments it reads on startup.
http_confdir() {
    local dir
    for dir in /etc/httpd/conf.d /etc/apache2/conf-enabled /etc/apache2/conf.d; do
        [ -d "$dir" ] && { echo "$dir"; return 0; }
    done
    return 1
}

pkgdir_for() { echo "$(installdir)/$OSVERS/$1"; }

# The names the loaders and the resolver ask for, arrived at the way the
# firmware arrives at them: an encoding wrong by one digit produces no error
# anywhere. Calls provtest's own encoders rather than a second implementation in
# shell, which would be a second chance to be wrong with no unit tests.
netutil() {
    local fn=$1
    shift
    python3 -c 'import sys
sys.path.insert(0, sys.argv[1])
from provtest_lib import netutil
sys.stdout.write(str(getattr(netutil, sys.argv[2])(*sys.argv[3:])))' \
        "$PROVTEST/src" "$fn" "$@"
}

hex_ip()       { netutil hex_ip "$1"; }
# As many hex digits as the netmask covers, rounded up: a /24 is six.
hex_net()      { netutil hex_net "$1" "$2"; }
dashed_mac()   { netutil dashed_mac "$1"; }
reverse_name() { netutil reverse_name "$1"; }

# A port nothing answers on: one for the web server, one for the control half of
# P-39. Ports already handed out are passed in, so the two differ.
free_port() {
    local port taken
    for port in 8899 8898 8897 8896; do
        for taken in "$@"; do
            [ "$port" = "$taken" ] && continue 2
        done
        ss -ltnH "( sport = :$port )" 2>/dev/null | grep -q . || { echo "$port"; return 0; }
    done
    return 1
}

# Where the x86_64 genesis kernel lives, if mknb has ever run here. The fixture
# cannot build it.
genesis_kernel() { echo "$(tftpdir)/xcat/genesis.kernel.$NODE_ARCH"; }
have_genesis()   { [ -f "$(genesis_kernel)" ]; }

# --- what was changed, so teardown is exact -------------------------------

# Every file the fixture creates is recorded; teardown removes exactly those.
record_file() { echo "$1" >> "$STATE/files"; }
record_dir()  { echo "$1" >> "$STATE/dirs"; }

make_dir() {
    local dir=$1
    [ -d "$dir" ] && return 0
    mkdir -p "$dir" || die "cannot create $dir"
    record_dir "$dir"
}

write_file() {
    local path=$1
    make_dir "$(dirname "$path")"
    [ -f "$path" ] && die "$path already exists; refusing to overwrite it"
    cat > "$path" || die "cannot write $path"
    record_file "$path"
}

service_state() {
    systemctl is-active "$1" 2>/dev/null
}

# Start a daemon the suite needs, remembering whether it was already running.
ensure_running() {
    local unit=$1 was
    systemctl list-unit-files "$unit" >/dev/null 2>&1 || return 1
    was=$(service_state "$unit")
    echo "$unit $was" >> "$STATE/services"
    [ "$was" = active ] && return 0
    systemctl start "$unit" >/dev/null 2>&1 || return 1
    return 0
}

restore_services() {
    local unit was
    [ -f "$STATE/services" ] || return 0
    # On descriptor 3, for the reason given in do_teardown.
    while read -r unit was <&3; do
        [ -n "$unit" ] || continue
        if [ "$was" = active ]; then
            systemctl restart "$unit" >/dev/null 2>&1
        else
            systemctl stop "$unit" >/dev/null 2>&1
        fi
    done 3< "$STATE/services"
}

# A daemon up with no socket makes every scenario fail on a timeout, which reads
# as an xCAT fault. So each stage asks who holds its port first.
serving() {
    local proto=$1 port=$2 flag
    command -v ss >/dev/null 2>&1 || return 0
    [ "$proto" = udp ] && flag=-uanH || flag=-lanH
    ss $flag "( sport = :$port )" 2>/dev/null | grep -q .
}

assert_serving() {
    local proto=$1 port=$2 what=$3
    serving "$proto" "$port" \
        || die "nothing holds $proto/$port, so $what cannot answer"
}

# The first of these unit names this machine has: the name is the distribution's
# choice and nothing else about the service differs.
first_unit() {
    local unit
    for unit in "$@"; do
        systemctl list-unit-files "$unit" >/dev/null 2>&1 && { echo "$unit"; return 0; }
    done
    return 1
}

dns_unit()  { first_unit named.service bind9.service named-chroot.service; }
http_unit() { first_unit httpd.service apache2.service; }
tftp_unit() { first_unit tftp.socket tftpd-hpa.service xinetd.service; }

# --- check ----------------------------------------------------------------

do_check() {
    local leftover pkgdir port
    [ "$(id -u)" = 0 ] || skip "the wire cases bind source addresses and low ports, which needs root"
    command -v ip >/dev/null 2>&1 || skip "iproute2 is not installed"
    command -v nodeset >/dev/null 2>&1 || skip "nodeset is not on PATH, so this is not a management node"
    command -v makedns >/dev/null 2>&1 || skip "makedns is not on PATH, so this is not a management node"
    # -f rather than -x: the fixture runs it as `python3 src/provtest`, and
    # dh_install keeps the source mode on Debian.
    [ -f "$PROVTEST/src/provtest" ] || skip "provtest is not installed under $PROVTEST"

    # The clients the scenarios are driven with. They are real binaries on
    # purpose: a node fetches with the same ones.
    command -v dig >/dev/null 2>&1 || skip "dig is not installed (bind-utils / dnsutils)"
    command -v curl >/dev/null 2>&1 || skip "curl is not installed"
    command -v tftp >/dev/null 2>&1 || skip "a tftp client is not installed (tftp / tftp-hpa)"

    ip link add "${IF_SRV}probe" type veth peer name "${IF_CLI}probe" 2>/dev/null \
        || skip "this kernel has no veth support"
    ip link del "${IF_SRV}probe" 2>/dev/null

    # Not a missing feature: this machine already uses something the fixture
    # would take over.
    ip -o addr show | grep -qw "$SRV_IP" && skip "$SRV_IP is already configured on this machine"
    ip link show "$IF_SRV" >/dev/null 2>&1 && skip "$IF_SRV already exists"
    ip netns list 2>/dev/null | grep -qw "$NETNS" && skip "a network namespace called $NETNS already exists"
    # Every name, not just $NODE: a half-finished teardown leaves some behind,
    # and setup would record them as the state to restore to.
    for leftover in "$NODE" "$PXE_NODE" "$BOOT_NODE" "$XNBA_NODE" "$PTB_NODE" \
                    "$MASTER_NODE"; do
        lsdef "$leftover" >/dev/null 2>&1 \
            && skip "a node called $leftover is already defined"
    done
    lsdef -t network -o "$NETOBJ" >/dev/null 2>&1 && skip "a network called $NETOBJ is already defined"
    pkgdir=$(pkgdir_for "$NODE_ARCH")
    [ -d "$pkgdir" ] && skip "$pkgdir already exists"

    # P-43 needs a network xCAT does not manage; if this machine manages it, the
    # scenario asserts the opposite of what it says.
    lsdef -t network -i net -c 2>/dev/null | grep -q "net=$FOREIGN_NET\$" \
        && skip "$FOREIGN_NET is a managed network here, so the foreign-address case cannot be run"

    # Warned, not refused: the other stages do not need the web server, and
    # setup may yet move it to a port of its own.
    port=$(httpport)
    http_serves_xcat "$port" \
        || say "the web server on port $port answers 404 for $(tftpdir); unless setup can move the web server, the HTTP stages will be left out"

    say "environment is able to run the wire cases"
}

# --- setup ----------------------------------------------------------------

# A minimal install tree: the four files the install path fetches. Fabricated
# rather than copied, because what is under test is whether xCAT serves and
# names what it was told about, not whether a distribution installs.
fabricate_tree() {
    local arch=$1 dir images
    dir=$(pkgdir_for "$arch")

    # Where each architecture's media keeps its kernel, because that is where
    # xCAT looks (anaconda.pm:1402, anaconda.pm:167).
    case "$arch" in
        ppc64|ppc64le) images="ppc/$arch" ;;
        *)             images="images/pxeboot" ;;
    esac

    write_file "$dir/$images/vmlinuz" <<EOF
provtest placeholder kernel for $arch; never executed, only fetched.
EOF
    write_file "$dir/$images/initrd.img" <<EOF
provtest placeholder initrd for $arch; never executed, only fetched.
EOF
    # What P-36 fetches: repomd.xml is the first file any installer asks a
    # repository for.
    write_file "$dir/repodata/repomd.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<repomd xmlns="http://linux.duke.edu/metadata/repo"><revision>0</revision></repomd>
EOF
    write_file "$dir/.treeinfo" <<EOF
[general]
family = provtest
version = 9.99
arch = $arch
EOF
}

# The template mkinstall renders into /install/autoinst/<node>: P-35 fetches the
# rendered result, so a finished file would not do.
fabricate_template() {
    local path=$1
    write_file "$path" <<'EOF'
# provtest kickstart template. Rendered by mkinstall, fetched by the wire cases,
# never installed.
install
text
reboot
rootpw --iscrypted *
%post
#XCAT_KICKSTART_POST__
%end
EOF
}

# The grub2 network loader. xCAT does not build this: grub2.pm refuses to write
# a node's config without it (grub2.pm:309-311) and expects the administrator to
# have put it there. So the fixture builds a real one with grub2-mkimage -- P-09
# asserts a node can fetch it, and an empty file would stop at the firmware.
# Without the modules there is nothing to build from, and the stage says so.
provide_grub2_loader() {
    local arch=$1 tftp path platform
    tftp=$(tftpdir)
    path="$tftp/boot/grub2/grub2.$arch"
    [ -f "$path" ] && return 0

    command -v grub2-mkimage >/dev/null 2>&1 || return 1
    case "$arch" in
        x86_64) platform=x86_64-efi ;;
        *)      return 1 ;;
    esac
    [ -d "/usr/lib/grub/$platform" ] || return 1

    make_dir "$(dirname "$path")"
    grub2-mkimage -O "$platform" -o "$path" -p /boot/grub2 \
        tftp http efinet net linux normal configfile echo test search \
        >/dev/null 2>&1 || { rm -f "$path"; return 1; }
    record_file "$path"
    say "built a grub2 network loader at $path"
    return 0
}

# Move the web server to a port the cluster does not use yet. The aliases in
# xcat.conf are server-wide, so one Listen line is the whole change -- but only
# Apache reads that directory, so this is attempted and not assumed. Everything
# it wrote is undone when the server will not answer.
provide_http_port() {
    local port=$1 dir path unit
    dir=$(http_confdir) || return 1
    unit=$(http_unit)   || return 1
    path="$dir/provtest-httpport.conf"
    write_file "$path" <<EOF
# Added by provfixture.sh so the cluster's site.httpport has something behind
# it. Removed by \`provfixture.sh teardown\`.
Listen $port
EOF
    ensure_running "$unit" || { rm -f "$path"; return 1; }
    # Restarted, not started: the Listen line is only read at startup.
    systemctl restart "$unit" >/dev/null 2>&1
    serving tcp "$port" && return 0
    rm -f "$path"
    systemctl restart "$unit" >/dev/null 2>&1
    return 1
}

define_osimage() {
    local name=$1 arch=$2 tmpl=$3
    mkdef -f -t osimage -o "$name" imagetype=linux provmethod=install \
        osname=Linux osvers="$OSVERS" osarch="$arch" osdistroname="$OSVERS-$arch" \
        profile=compute \
        pkgdir="$(pkgdir_for "$arch")" template="$tmpl" \
        || die "cannot define the osimage $name"
    echo "$name" >> "$STATE/osimages"
}

define_node() {
    local name=$1 ip=$2 mac=$3 arch=$4 netboot=$5 image=$6
    shift 6
    mkdef -f -t node -o "$name" groups=provtest ip="$ip" mac="$mac" arch="$arch" \
        netboot="$netboot" provmethod="$image" tftpserver="$SRV_IP" \
        xcatmaster="$SRV_IP" nfsserver="$SRV_IP" status=defined "$@" \
        || die "cannot define the node $name"
    echo "$name" >> "$STATE/nodes"
}

do_setup() {
    local tmpl http dns tftp
    mkdir -p "$STATE" || die "cannot create $STATE"
    : > "$STATE/files"; : > "$STATE/dirs"
    : > "$STATE/nodes"; : > "$STATE/osimages"; : > "$STATE/services"

    # Recorded before it is changed, so teardown is exact rather than a guess.
    tabdump site > "$STATE/site.csv" || die "cannot read the site table"
    cp -f /etc/hosts "$STATE/hosts" || die "cannot save /etc/hosts"
    save_dns_config

    ip link add "$IF_SRV" type veth peer name "$IF_CLI" || die "cannot create the veth pair"
    echo done > "$STATE/veth"
    ip addr add "$SRV_IP/$PREFIX" dev "$IF_SRV" || die "cannot address $IF_SRV"
    ip link set "$IF_SRV" up || die "cannot bring up $IF_SRV"

    # The foreign network is routed to rather than put on this interface, and
    # that is the test: xcatd asks NetworkUtils::nodeonmynet, which counts only
    # directly attached routes. An address on $IF_SRV would quietly turn the
    # foreign client into a local one.
    ip route add "$FOREIGN_NET/$PREFIX" via "$NODE_IP" dev "$IF_SRV" \
        || die "cannot route $FOREIGN_NET/$PREFIX through $NODE_IP"

    # The client end lives in a namespace of its own because xcatd calls a
    # discovering machine back on TCP 3001 -- the port it listens on itself --
    # so a client sharing the management node's stack could never hold it. The
    # packets still cross a real wire.
    ip netns add "$NETNS" || die "cannot create the network namespace $NETNS"
    echo done > "$STATE/netns"
    ip link set "$IF_CLI" netns "$NETNS" || die "cannot move $IF_CLI into $NETNS"

    # The client end holds the node's address, the unknown one and the foreign
    # one. Which of the three a request leaves by is what separates the
    # scenarios that use them.
    in_ns ip addr add "$NODE_IP/$PREFIX" dev "$IF_CLI" || die "cannot address $IF_CLI"
    in_ns ip addr add "$UNKNOWN_IP/$PREFIX" dev "$IF_CLI" || die "cannot add $UNKNOWN_IP to $IF_CLI"
    in_ns ip addr add "$FOREIGN_IP/32" dev "$IF_CLI" || die "cannot add $FOREIGN_IP to $IF_CLI"
    in_ns ip link set lo up || die "cannot bring up lo in $NETNS"
    in_ns ip link set "$IF_CLI" up || die "cannot bring up $IF_CLI"

    mkdef -f -t network -o "$NETOBJ" net="$NET" mask="$MASK" mgtifname="$IF_SRV" \
        gateway="$SRV_IP" tftpserver="$SRV_IP" nameservers="$SRV_IP" \
        domain="$DOMAIN" \
        || die "cannot define the network $NETOBJ"
    echo done > "$STATE/network"

    # NetworkUtils::nodeonmynet caches the routing table per pid, so a daemon
    # older than the veth would decide P-43 against a table that no longer
    # exists.
    if systemctl restart xcatd >/dev/null 2>&1; then
        local waited=0
        until lsxcatd -v >/dev/null 2>&1; do
            waited=$((waited + 1))
            [ "$waited" -gt 30 ] && die "xcatd did not come back after a restart"
            sleep 1
        done
    else
        say "xcatd was not restarted; the discovery stage may judge the foreign address against a stale routing table"
    fi

    # The daemons a node fetches from, started before anything is generated:
    # whether the web server can be moved decides site.httpport, which the
    # plugins read when they write the node's boot configuration. A port already
    # held needs no unit -- xcatconfig starts in.tftpd itself.
    serving udp 53 || { dns=$(dns_unit)   && ensure_running "$dns";  } \
        || say "no DNS unit was started; the DNS stage will say so"
    serving udp 69 || { tftp=$(tftp_unit) && ensure_running "$tftp"; } \
        || say "no TFTP unit was started; the TFTP stage will say so"

    # site.master lands on the kernel command line as xcatd=<addr>:3001, and
    # site.domain is the zone makedns writes. Both restored from site.csv.
    chdef -t site -o clustersite master="$SRV_IP" domain="$DOMAIN" \
        || die "cannot set site.master and site.domain"

    # Moved only if the move takes: a cluster the fixture cannot reconfigure
    # keeps its port, and the HTTP stage asserts the other half of P-39.
    HTTPPORT=$(free_port) || HTTPPORT=
    if [ -n "$HTTPPORT" ] && provide_http_port "$HTTPPORT"; then
        chdef -t site -o clustersite httpport="$HTTPPORT" \
            || die "cannot set site.httpport"
    else
        HTTPPORT=
        say "the web server was left on port $(httpport); the default-port half of the HTTP stage will run instead"
    fi

    provide_grub2_loader "$NODE_ARCH" \
        || say "no grub2 network loader could be built; the grub2 scenarios will be left out"

    tmpl="$(installdir)/custom/install/provtest/provtest.tmpl"
    fabricate_template "$tmpl"
    fabricate_tree "$NODE_ARCH"
    fabricate_tree "$PTB_ARCH"
    define_osimage "$OSIMAGE" "$NODE_ARCH" "$tmpl"
    define_osimage "$PTB_OSIMAGE" "$PTB_ARCH" "$tmpl"

    # hostnames= is what becomes the CNAME P-04 asks for, by way of /etc/hosts
    # and makedns.
    define_node "$NODE" "$NODE_IP" "$NODE_MAC" "$NODE_ARCH" "$NODE_NETBOOT" \
        "$OSIMAGE" hostnames="$ALIAS"
    define_node "$PXE_NODE" "$PXE_IP" "$PXE_MAC" "$NODE_ARCH" pxe "$OSIMAGE"
    define_node "$BOOT_NODE" "$BOOT_IP" "$BOOT_MAC" "$NODE_ARCH" pxe "$OSIMAGE"
    define_node "$XNBA_NODE" "$XNBA_IP" "$XNBA_MAC" "$NODE_ARCH" xnba "$OSIMAGE"
    define_node "$PTB_NODE" "$PTB_IP" "$PTB_MAC" "$PTB_ARCH" petitboot "$PTB_OSIMAGE"

    # The master gets a definition so P-07 has a name to resolve. Never
    # provisioned and never nodeset.
    mkdef -f -t node -o "$MASTER_NODE" groups=provtest ip="$SRV_IP" \
        || die "cannot define $MASTER_NODE"
    echo "$MASTER_NODE" >> "$STATE/nodes"

    makehosts "$MASTER_NODE,$NODE,$PXE_NODE,$BOOT_NODE,$XNBA_NODE,$PTB_NODE" \
        || die "makehosts failed"
    echo done > "$STATE/hostsadded"

    do_generate || return 1

    say "fixture is up on $IF_SRV/$IF_CLI, node $NODE at $NODE_IP"
}

save_dns_config() {
    local f
    for f in /etc/named.conf /etc/bind/named.conf /etc/bind/named.conf.local; do
        [ -f "$f" ] && cp -f "$f" "$STATE/$(echo "$f" | tr / _)"
    done
    # The zone tree as a whole: makedns removes inside it, and a file-by-file
    # restore would miss that.
    for f in /var/named /var/lib/bind /etc/bind; do
        [ -d "$f" ] && tar -C / -czf "$STATE/$(echo "$f" | tr / _).tgz" "${f#/}" 2>/dev/null
    done
}

restore_dns_config() {
    local f saved
    for f in /var/named /var/lib/bind /etc/bind; do
        saved="$STATE/$(echo "$f" | tr / _).tgz"
        [ -f "$saved" ] && { rm -rf "$f"; tar -C / -xzf "$saved" 2>/dev/null; }
    done
    for f in /etc/named.conf /etc/bind/named.conf /etc/bind/named.conf.local; do
        saved="$STATE/$(echo "$f" | tr / _)"
        [ -f "$saved" ] && cp -f "$saved" "$f"
    done
}

# The file a node of each netboot type is given, by the name the loader asks for
# it by. The fixture's own arithmetic, not a question put to xCAT.
node_config() {
    local netboot=$1 node=$2 ip=$3 tftp
    tftp=$(tftpdir)
    case "$netboot" in
        grub2*)    echo "$tftp/boot/grub2/grub.cfg-$(hex_ip "$ip")" ;;
        pxe)       echo "$tftp/pxelinux.cfg/$(hex_ip "$ip")" ;;
        xnba)      echo "$tftp/xcat/xnba/nodes/$node" ;;
        petitboot) echo "$tftp/petitboot/$node" ;;
    esac
}

generated() {
    local path
    path=$(node_config "$1" "$2" "$3")
    [ -n "$path" ] && [ -e "$path" ]
}

# Generate the artefacts a node fetches and the records that decide whose they
# are. Separate from setup so run-ordering can regenerate after changing one
# thing. nodeset is run for the files it writes, not the status it exits with:
# it reports an unreachable DHCP backend as a failure of the whole command,
# having already written every boot configuration. So each artefact is looked
# for by name.
do_generate() {
    makedns -n >/dev/null || die "makedns -n failed"
    echo done > "$STATE/dns"

    nodeset "$NODE,$PXE_NODE,$XNBA_NODE" osimage="$OSIMAGE" >/dev/null 2>&1
    generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
        || die "nodeset wrote no $NODE_NETBOOT configuration for $NODE"
    generated pxe "$PXE_NODE" "$PXE_IP" \
        || die "nodeset wrote no pxelinux configuration for $PXE_NODE"
    generated xnba "$XNBA_NODE" "$XNBA_IP" \
        || die "nodeset wrote no xnba configuration for $XNBA_NODE"

    # The ppc64le node is set separately: a management node that cannot generate
    # for another architecture skips the petitboot stage instead of failing
    # setup.
    nodeset "$PTB_NODE" osimage="$PTB_OSIMAGE" >/dev/null 2>&1
    generated petitboot "$PTB_NODE" "$PTB_IP" \
        || say "no petitboot configuration was written for $PTB_NODE; the petitboot stage will say so"

    nodeset "$BOOT_NODE" boot >/dev/null 2>&1
    generated pxe "$BOOT_NODE" "$BOOT_IP" \
        || die "nodeset $BOOT_NODE boot wrote no configuration for $BOOT_NODE"

    # The per-network discovery configurations name every network xCAT knows, so
    # the fixture's appears only once mknb has run again. `-c` rewrites them
    # from the images already under $tftpdir and rebuilds nothing.
    if have_genesis; then
        record_file "$(tftpdir)/boot/grub2/grub.cfg-$(hex_net "$NET" "$PREFIX")"
        record_file "$(tftpdir)/pxelinux.cfg/$(hex_net "$NET" "$PREFIX")"
        local nets
        nets="$(tftpdir)/xcat/xnba/nets/$NET_FILE"
        record_file "$nets" ; record_file "$nets.elilo" ; record_file "$nets.uefi"
        mknb "$NODE_ARCH" -c >/dev/null 2>&1 \
            || say "mknb -c reported an error; the genesis stage will say so"
    fi

    echo done > "$STATE/nodeset"
    say "artefacts generated for $DESTINY"
}

# --- running --------------------------------------------------------------

# Everything a node does runs from the node's namespace, so the source address,
# the free ports and the routes are the node's own.
in_ns() { ip netns exec "$NETNS" "$@"; }

provtest_run() {
    ( cd "$PROVTEST" && in_ns python3 src/provtest run "$@" )
}

# What every scenario file is told: who is asked, and from whose address. Named
# once, so a new setting is one edit and not nineteen.
COMMON=(--set server="$SRV_IP" --set client="$NODE_IP")

# The node put back to the state setup left it in. Checked rather than assumed,
# because nodeset exits non-zero when it cannot reach the DHCP backend and still
# writes the file: the file is the evidence, not the exit status.
reset_node() {
    nodeset "$NODE" osimage="$OSIMAGE" >/dev/null 2>&1
    generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
        || die "nodeset wrote no $NODE_NETBOOT configuration for $NODE"
}

# Stage 1. The forwarded-name scenario is selected separately: it needs a
# working forwarder, which is a fact about the runner's network, not about xCAT.
do_run_dns() {
    local rc=0 scenarios
    assert_serving udp 53 "the name server"

    scenarios="-s node-forward -s node-reverse -s node-alias -s local-nxdomain -s master-resolves"
    provtest_run $scenarios \
        "${COMMON[@]}" \
        --set node="$NODE" --set domain="$DOMAIN" \
        --set nodeip="$NODE_IP" --set revname="$(reverse_name "$NODE_IP")" \
        --set alias="$ALIAS" --set master="$MASTER_NODE.$DOMAIN" \
        --set missing="$MISSING" --set forwarded="$FORWARDED" \
        --set net="$NET/$PREFIX" \
        conf/dns.conf || rc=1

    if dig +short +time=5 +tries=1 "$FORWARDED" A >/dev/null 2>&1 && \
       [ -n "$(dig +short +time=5 +tries=1 "$FORWARDED" A 2>/dev/null)" ]; then
        provtest_run -s forwarded-name \
            "${COMMON[@]}" \
            --set node="$NODE" --set domain="$DOMAIN" \
            --set nodeip="$NODE_IP" --set revname="$(reverse_name "$NODE_IP")" \
            --set alias="$ALIAS" --set master="$MASTER_NODE.$DOMAIN" \
            --set missing="$MISSING" --set forwarded="$FORWARDED" \
            --set net="$NET/$PREFIX" \
            conf/dns.conf || rc=1
    else
        stage_skip "$FORWARDED does not resolve from this machine, so there is no forwarder to test"
    fi
    return $rc
}

# Stage 3. One file per netboot method, one node per file: the method is an
# attribute of the node, so one node cannot answer for all four.
do_run_tftp() {
    local rc=0 loader tftp scenarios xnba port
    assert_serving udp 69 "the TFTP server"
    tftp=$(tftpdir)

    # The loader comes from a package or from copycds; the fixture cannot create
    # it. Where it is absent the two scenarios that fetch it are left out rather
    # than satisfied with a placeholder the fixture wrote.
    loader="boot/grub2/grub2.$NODE_ARCH"
    if [ -f "$tftp/$loader" ]; then
        scenarios=""
    else
        scenarios="-s grub2-node-config -s grub2-config-by-mac -s grub2-kernel-and-initrd -s tftp-escape"
        stage_skip "$tftp/$loader is not present, so the loader fetches are left out"
    fi
    provtest_run $scenarios \
        "${COMMON[@]}" \
        --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")" \
        --set macdashes="$(dashed_mac "$NODE_MAC")" --set mac="$NODE_MAC" \
        --set loader="$loader" --set bootfile="boot/grub2/grub2-$NODE" \
        --set master="$SRV_IP" --set xcatport="$XCATPORT" --set destiny="$DESTINY" \
        conf/tftp-grub2.conf || rc=1

    provtest_run \
        "${COMMON[@]}" \
        --set node="$PXE_NODE" --set hexip="$(hex_ip "$PXE_IP")" \
        --set master="$SRV_IP" --set xcatport="$XCATPORT" --set destiny="$DESTINY" \
        --set bootnode="$BOOT_NODE" \
        conf/tftp-pxelinux.conf || rc=1

    # The xnba case is the one that crosses transports, so a web server serving
    # the wrong tree fails it for an unrelated reason. The script is asserted
    # either way; the kernel it names only where something serves it.
    port=$(httpport)
    if http_serves_xcat "$port"; then
        xnba="-s xnba-script -s xnba-kernel"
    else
        xnba="-s xnba-script"
        stage_skip "the web server on port $port does not serve $tftp, so the kernel half of the xnba case is left out"
    fi
    # shellcheck disable=SC2086
    provtest_run $xnba \
        "${COMMON[@]}" \
        --set node="$XNBA_NODE" --set httpport="$port" \
        conf/tftp-xnba.conf || rc=1

    if [ -f "$tftp/petitboot/$PTB_NODE" ]; then
        provtest_run \
            "${COMMON[@]}" \
            --set node="$PTB_NODE" --set hexip="$(hex_ip "$PTB_IP")" \
            --set master="$SRV_IP" --set xcatport="$XCATPORT" --set destiny="$DESTINY" \
            conf/tftp-petitboot.conf || rc=1
    else
        stage_skip "no petitboot config was generated for $PTB_NODE on this management node"
    fi
    return $rc
}

# Stage 4.
do_run_http() {
    local port other select
    port=$(httpport)
    assert_serving tcp "$port" "the web server"
    # Every scenario here fetches a path xCAT aliases, so a web server without
    # them fails all nine for one reason. Said once, as a skip.
    http_serves_xcat "$port" || {
        stage_skip "the web server on port $port answers 404 for $(tftpdir), so it is not the one xCAT configured and the HTTP stage is left out"
        return 0
    }
    other=$(free_port "$port") || die "no port is free for the control half of the port case"

    # P-39 has two halves and a cluster is on one side or the other: a node is
    # told a port, or told none and expected to use the default. The port the
    # cluster is on decides which is asserted.
    select="-s install-tree -s tftp-tree-over-http -s urls-the-node-was-given"
    select="$select -s outside-the-aliases -s postscripts-listing"
    if [ "$port" = 80 ]; then
        select="$select -s default-port-the-node-was-told"
    else
        select="$select -s port-the-node-was-told"
    fi

    # shellcheck disable=SC2086
    provtest_run $select \
        "${COMMON[@]}" \
        --set node="$NODE" --set httpport="$port" --set otherport="$other" \
        --set hexip="$(hex_ip "$NODE_IP")" \
        --set knownfile="boot/grub2/grub.cfg-$(hex_ip "$NODE_IP")" \
        --set installpath="autoinst/$NODE" \
        --set repofile="repodata/repomd.xml" \
        conf/http.conf
}

# Stage 5. The per-network artefacts, which exist only once genesis has been
# built: the fixture cannot create them without running mknb.
do_run_genesis() {
    local tftp hexnet select=""
    have_genesis || { stage_skip "genesis has not been built here ($(genesis_kernel) is missing); run mknb $NODE_ARCH"; return 0; }
    tftp=$(tftpdir); hexnet=$(hex_net "$NET" "$PREFIX")

    # One scenario per loader family, and only the families this architecture is
    # given: selecting by name means a family that is not written is absent from
    # the report rather than passing vacuously.
    [ -e "$tftp/pxelinux.cfg/$hexnet" ] &&
        select="$select -s pxelinux-discovery-config -s genesis-images-pxelinux"
    [ -e "$tftp/xcat/xnba/nets/$NET_FILE" ] &&
        select="$select -s xnba-discovery-config"
    [ -e "$tftp/boot/grub2/grub.cfg-$hexnet" ] &&
        select="$select -s grub2-discovery-config -s genesis-images-grub2"

    [ -n "$select" ] || { stage_skip "mknb has written no configuration for $NET/$PREFIX, so there is nothing a machine without a definition would fetch"; return 0; }
    assert_serving udp 69 "the TFTP server"

    # Unquoted on purpose: the selection is a list this script built itself.
    # shellcheck disable=SC2086
    provtest_run $select \
        "${COMMON[@]}" \
        --set hexnet="$hexnet" --set netfile="$NET_FILE" \
        --set master="$SRV_IP" --set xcatport="$XCATPORT" \
        conf/discovery-artefacts.conf
}

# Stages 6 and 7, in the order a discovering machine does them: it asks for a
# slot before it announces itself.
do_run_discovery() {
    local rc=0
    assert_serving udp "$XCATPORT" "the xcatd flow-control listener"

    provtest_run \
        "${COMMON[@]}" \
        conf/flowcontrol.conf || rc=1

    provtest_run \
        "${COMMON[@]}" \
        --set foreign="$FOREIGN_IP" \
        conf/findme.conf || rc=1
    return $rc
}

# Stages 9 to 12, in the order a node does them: chain-advances moves the node
# off `install`, so everything asserting destiny=install has to run first.
do_run_xcatd() {
    local rc=0
    assert_serving tcp "$XCATPORT" "xcatd"

    provtest_run \
        "${COMMON[@]}" \
        --set xcatport="$XCATPORT" --set refused=rpower --set node="$NODE" \
        conf/xcatd-policy.conf || rc=1

    provtest_run \
        "${COMMON[@]}" \
        --set unknown="$UNKNOWN_IP" --set node="$NODE" \
        --set xcatport="$XCATPORT" --set monitorport="$MONITORPORT" \
        conf/xcatd-postscript.conf || rc=1

    provtest_run \
        "${COMMON[@]}" \
        --set xcatport="$XCATPORT" --set credtype=xcat_server_cred \
        conf/xcatd-credentials.conf || rc=1

    # Last, and after the node has been reset, because these scenarios end by
    # advancing the chain: nextdestiny is a write, not a question. Resetting is
    # what makes the stage repeatable.
    reset_node

    provtest_run \
        "${COMMON[@]}" \
        --set unknown="$UNKNOWN_IP" --set node="$NODE" \
        --set destiny="$DESTINY" --set master="$SRV_IP" --set xcatport="$XCATPORT" \
        conf/xcatd-destiny.conf || rc=1
    return $rc
}

# Stage 13.
do_run_monitor() {
    assert_serving tcp "$MONITORPORT" "the xcatd install monitor"

    provtest_run \
        "${COMMON[@]}" \
        --set unknown="$UNKNOWN_IP" --set monitorport="$MONITORPORT" \
        --set xcatport="$XCATPORT" \
        conf/monitor.conf
}

# Failing at exactly one place. Each scenario needs the cluster in a different
# state, so they are driven in order and selected by name.
do_run_ordering() {
    local rc=0 flags
    assert_serving tcp "$XCATPORT" "xcatd"

    # The same question asked of a cluster in three states, so the settings are
    # built once rather than copied three times.
    flags=("${COMMON[@]}"
           --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")"
           --set xcatport="$XCATPORT" --set unreachable="$UNREACHABLE_IP"
           --set master="$SRV_IP"
           --set destiny="$DESTINY" --set second="$SECOND_DESTINY")

    # This stage ends by withdrawing the node's name and everything before that
    # needs it: nodeset resolves the node to name the config it writes.
    if [ -f "$STATE/ptrgone" ]; then
        makehosts "$NODE" >/dev/null 2>&1 || say "makehosts $NODE reported an error"
        makedns -n >/dev/null 2>&1 || say "makedns -n reported an error"
        rm -f "$STATE/ptrgone"
    fi

    # Back to the starting state: P-74 is about a node still set to install
    # being told to discover itself anyway.
    reset_node

    provtest_run -s unreachable-master "${flags[@]}" conf/ordering.conf || rc=1

    # P-75 before P-74, forced rather than chosen: the second nodeset has to
    # resolve the node to name the config it writes, so it cannot run once the
    # name has been withdrawn.
    #
    # P-75: a second nodeset, to a state whose name the config must now carry.
    if have_genesis; then
        nodeset "$NODE" "$SECOND_DESTINY" >/dev/null 2>&1
        generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
            || die "nodeset $NODE $SECOND_DESTINY wrote no $NODE_NETBOOT configuration"
        provtest_run -s state-replaced "${flags[@]}" conf/ordering.conf || rc=1
    else
        stage_skip "genesis has not been built here, so there is no second state to set"
    fi

    # P-74: the node's name taken out of resolution, nothing else. Both the zone
    # and /etc/hosts, because xcatd resolves the client address through nsswitch:
    # with the hosts entry left in, the name still resolves and the scenario
    # would pass by not being run.
    makedns -d "$NODE" >/dev/null 2>&1 || say "makedns -d $NODE reported an error"
    makehosts -d "$NODE" >/dev/null 2>&1 || say "makehosts -d $NODE reported an error"
    echo done > "$STATE/ptrgone"
    provtest_run -s missing-ptr "${flags[@]}" conf/ordering.conf || rc=1

    return $rc
}

# What a withdrawn node must stop resolving to. Run last and on its own: it
# asserts the opposite of the DNS stage about the same names.
do_run_dns_removal() {
    assert_serving udp 53 "the name server"

    makedns -d "$NODE" >/dev/null 2>&1 || say "makedns -d $NODE reported an error"
    echo done > "$STATE/ptrgone"

    provtest_run \
        "${COMMON[@]}" \
        --set node="$NODE" --set domain="$DOMAIN" \
        --set revname="$(reverse_name "$NODE_IP")" \
        conf/dns-removal.conf
}

# --- teardown -------------------------------------------------------------

do_teardown() {
    local name path dir
    [ -d "$STATE" ] || return 0

    # Every loop reads its list on file descriptor 3, because the xCAT clients
    # inside them read standard input themselves: on the first iteration the
    # command swallows the rest of the file and teardown stops after one name,
    # leaving nodes and a rewritten site table behind.
    if [ -f "$STATE/nodes" ]; then
        while read -r name <&3; do
            [ -n "$name" ] || continue
            nodeset "$name" offline >/dev/null 2>&1
            makedns -d "$name" >/dev/null 2>&1
            makehosts -d "$name" >/dev/null 2>&1
            rmdef "$name" >/dev/null 2>&1
        done 3< "$STATE/nodes"
    fi
    if [ -f "$STATE/osimages" ]; then
        while read -r name <&3; do
            [ -n "$name" ] && rmdef -t osimage -o "$name" >/dev/null 2>&1
        done 3< "$STATE/osimages"
    fi
    [ -f "$STATE/network" ] && rmdef -t network -o "$NETOBJ" >/dev/null 2>&1

    # What nodeset offline did not take with it. It is not reliable here: it
    # exits as soon as it cannot reach the DHCP backend, and leaves the kernel
    # and initrd it staged whatever happens. So the artefacts are removed by
    # name, and every name is one this fixture created.
    local tftp
    tftp=$(tftpdir)
    # Guarded: the one recursive removal here must not become the whole
    # directory if a name ever arrives empty.
    for name in "$OSIMAGE" "$PTB_OSIMAGE"; do
        [ -n "$name" ] && rm -rf "$tftp/xcat/osimage/$name"
    done
    # One node produces several files: xnba writes .uefi and .elilo beside the
    # script, grub2 writes both <node> and grub2-<node>. The globs are anchored
    # on a node name this fixture defined.
    for name in "$NODE" "$PXE_NODE" "$BOOT_NODE" "$XNBA_NODE" "$PTB_NODE"; do
        rm -f "$tftp/pxelinux.cfg/$name" "$tftp/petitboot/$name" \
              "$tftp/xcat/xnba/nodes/$name" "$tftp/xcat/xnba/nodes/$name".* \
              "$tftp/boot/grub2/$name" "$tftp/boot/grub2/grub2-$name"
    done
    for path in "$NODE_IP" "$PXE_IP" "$BOOT_IP" "$XNBA_IP" "$PTB_IP"; do
        name=$(hex_ip "$path")
        rm -f "$tftp/pxelinux.cfg/$name" "$tftp/boot/grub2/grub.cfg-$name" \
              "$tftp/$name"
    done
    # And the per-network ones mknb writes. The xnba form is named after the
    # network and its prefix rather than in hex.
    name=$(hex_net "$NET" "$PREFIX")
    rm -f "$tftp/pxelinux.cfg/$name" "$tftp/boot/grub2/grub.cfg-$name" \
          "$tftp/xcat/xnba/nets/$NET_FILE"

    # The generated artefacts: what is left is what this fixture put there
    # itself.
    if [ -f "$STATE/files" ]; then
        while read -r path <&3; do
            [ -n "$path" ] && rm -f "$path"
        done 3< "$STATE/files"
    fi
    if [ -f "$STATE/dirs" ]; then
        # Deepest first, and only if empty: a directory that still has
        # something in it was not this fixture's alone.
        sort -r "$STATE/dirs" | while read -r dir; do
            [ -n "$dir" ] && rmdir -p "$dir" 2>/dev/null
        done
    fi

    # The namespace goes first: deleting it takes the client end of the pair
    # with it.
    [ -f "$STATE/netns" ] && ip netns del "$NETNS" >/dev/null 2>&1
    [ -f "$STATE/veth" ] && ip link del "$IF_SRV" >/dev/null 2>&1

    # tabrestore replaces the table wholesale, which is what is wanted here:
    # site.master and site.domain go back to what they were, unset included.
    [ -f "$STATE/site.csv" ] && tabrestore "$STATE/site.csv" >/dev/null 2>&1
    [ -f "$STATE/hosts" ] && cp -f "$STATE/hosts" /etc/hosts

    restore_dns_config
    # Regenerated from the restored configuration, so a machine that was serving
    # its own zones is serving them again.
    makedns -n >/dev/null 2>&1
    restore_services

    rm -rf "$STATE"
    say "fixture removed"
}

dispatch() {
    case "${1:-}" in
    check)           do_check ;;
    setup)           do_setup ;;
    generate)        do_generate ;;
    run-dns)         do_run_dns ;;
    run-tftp)        do_run_tftp ;;
    run-http)        do_run_http ;;
    run-genesis)     do_run_genesis ;;
    run-discovery)   do_run_discovery ;;
    run-xcatd)       do_run_xcatd ;;
    run-monitor)     do_run_monitor ;;
    run-ordering)    do_run_ordering ;;
    run-dns-removal) do_run_dns_removal ;;
    teardown)        do_teardown ;;
    *)               die "usage: $0 {check|setup|generate|run-dns|run-tftp|run-http|run-genesis|run-discovery|run-xcatd|run-monitor|run-ordering|run-dns-removal|teardown}" ;;
    esac
}

dispatch "$@"
