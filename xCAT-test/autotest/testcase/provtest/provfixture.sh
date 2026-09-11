#!/bin/bash
#
# The xCAT side of the provtest wire cases.
#
# provtest itself never reads the xCAT database and never runs an xCAT
# command -- that is the whole point of it, and it is why the same .conf files
# can be pointed at any management node. Everything that *does* know about
# xCAT lives here.
#
# It builds a self-contained provisioning network out of a veth pair, so the
# wire cases have something real to talk to on a management node that has no
# spare NIC -- a single-node CI runner, most of all. The server end carries the
# management address; the client end carries the node's own address, because on
# this chain the source address *is* the credential: xcatd names a client by
# the reverse lookup of the address its request arrived from.
#
# Usage:
#     provfixture.sh check              is this machine able to run the wire cases
#     provfixture.sh setup              build the network, the nodes, the tree, the config
#     provfixture.sh run-dns            stage 1: the records a node and a server need
#     provfixture.sh run-tftp           stage 3: one netboot method per file
#     provfixture.sh run-http           stage 4: the two aliases, and the URLs the node was given
#     provfixture.sh run-genesis        stage 5: the per-network discovery artefacts
#     provfixture.sh run-discovery      stages 6 and 7: flow control, then findme
#     provfixture.sh run-xcatd          stages 9 to 12: destiny, policy, credentials, postscript
#     provfixture.sh run-monitor        stage 13: the install monitor on 3002
#     provfixture.sh run-ordering       failing at exactly one place: P-72, P-74, P-75
#     provfixture.sh run-dns-removal    what a withdrawn node must stop resolving to
#     provfixture.sh generate           re-run nodeset and makedns without rebuilding
#     provfixture.sh teardown           put everything back
#
# `setup` records what it changed under $STATE and `teardown` restores it, so
# a case that fails half way still leaves the machine serving its own config.
# What it changes is more than the DHCP fixture does: site.domain and
# site.master, the DNS configuration, and files under the tftp and install
# trees. All of it is saved before it is touched and put back afterwards, and
# `check` refuses to run at all if the addresses it would use are already
# spoken for.

set -u

IF_SRV=provtest0
IF_CLI=provtest1
# The namespace the client end of the pair lives in. See do_setup for why the
# node needs a network stack of its own and not just an address of its own.
NETNS=provtestns
NETOBJ=provtestnet
NET=10.99.1.0
MASK=255.255.255.0
PREFIX=24
# What mknb names the xnba per-network scripts: the network and its prefix,
# joined by an underscore because a slash cannot be a file name.
NET_FILE=10.99.1.0_24
SRV_IP=10.99.1.1
DOMAIN=provtest.cluster

# The management node, as a name. site.master is an address -- that is what
# goes on a kernel command line -- but P-07 is about the *name* a node is
# handed resolving, so the fixture gives the master a node definition of its
# own and DNS gets an A record out of it.
MASTER_NODE=provtestmn

# The node every stage is run as. The client end of the veth pair holds this
# address and nothing else holds it, so a request that arrives at xcatd from
# it can only have come from here.
#
# netboot is grub2-http rather than grub2: the HTTP entry is what P-39 reads
# the port out of, and the config a grub2 node gets names no port at all.
NODE=provtestcn
NODE_IP=10.99.1.11
NODE_MAC=52:54:00:dc:11:01
NODE_NETBOOT=grub2-http
ALIAS=provtestcn-eth0

# One node per netboot method whose config is named differently. They are
# separate nodes rather than one node reconfigured between stages because a
# node has one netboot method at a time, and a suite that changed it between
# files would be asserting against a machine that no longer exists.
#
# Their addresses are never bound to: only their files are fetched, and a TFTP
# fetch carries no identity.
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

# An address on the provisioning network that no node holds and no PTR names.
# Every "unknown client" scenario is this address and nothing else: the node
# address and this one differ in one thing, which is the point.
UNKNOWN_IP=10.99.1.201

# On-link, unassigned, and therefore unanswered: a TLS connection to it times
# out rather than being refused, which is what a node whose kernel command line
# names a dead master actually experiences.
UNREACHABLE_IP=10.99.1.250

# A network xCAT is not managing and is not attached to, for P-43. The client
# end carries the address; the management node only has a route to it, through
# the node, so the acknowledgement has somewhere to go without the network
# becoming one of its own. No network object is ever defined for it.
FOREIGN_NET=10.98.1.0
FOREIGN_IP=10.98.1.11

MISSING=nosuchnode
# A name in no local zone. Answering it needs a forwarder that works, which a
# CI runner may not have, so run-dns probes for one and leaves the scenario out
# rather than reporting a missing internet connection as an xCAT fault.
FORWARDED=example.com

XCATPORT=3001
MONITORPORT=3002

# The web port the cluster is told to use, if the fixture can arrange one.
# grub2 writes the port into the node's config only when site.httpport is
# something other than 80 (grub2.pm:267), so a cluster left on the default
# never exercises the path where four plugins each build a URL out of that
# attribute. The fixture therefore tries to move site.httpport and give the
# web server a Listen line for the new port, the way an administrator changing
# it has to -- and puts it back if the server will not take it, in which case
# the HTTP stage asserts the default-port half of P-39 instead. Filled in by
# setup; empty means the cluster's own port was left alone.
HTTPPORT=

# The install tree the nodes are pointed at. The version is deliberately one
# that cannot exist, so the fixture can neither find nor destroy a real tree
# that copycds put there: `check` refuses to run if the directory is present.
OSVERS=rhels9.99
OSIMAGE=provtest-install
PTB_OSIMAGE=provtest-install-ppc64
NODE_ARCH=x86_64
PTB_ARCH=ppc64le

# What nodeset is told to do, first and then again. The second state is `shell`
# rather than `boot`: P-75 asserts that the new destiny is in the rewritten
# config, and only a genesis destiny writes `destiny=` on the kernel command
# line at all -- a node told to boot from its disk is given a config with no
# kernel line to carry one.
DESTINY=install
SECOND_DESTINY=shell

STATE=/tmp/provtest-fixture
PROVTEST=/opt/xcat/share/xcat/tools/autotest/provtest
[ -d "$PROVTEST" ] || PROVTEST="$(cd "$(dirname "$0")/../../../provtest" 2>/dev/null && pwd)"

say()  { echo "provfixture: $*"; }
skip() { echo "provtest skipped: $*"; exit 1; }
die()  { echo "provfixture: $*" >&2; exit 1; }

# A stage that cannot run on this machine. Unlike `skip`, this is not a verdict
# on the whole case: the rest of the suite is still meaningful, so it says what
# is missing and passes.
stage_skip() { echo "provtest stage skipped: $*"; return 0; }

site_attr() {
    lsdef -t site clustersite -i "$1" -c 2>/dev/null \
        | grep "$1=" | awk -F= '{print $2}'
}

tftpdir() {
    local dir
    dir=$(site_attr tftpdir)
    echo "${dir:-/tftpboot}"
}

installdir() {
    local dir
    dir=$(site_attr installdir)
    echo "${dir:-/install}"
}

httpport() {
    local port
    port=$(site_attr httpport)
    echo "${port:-80}"
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

# The names the loaders ask for, computed here rather than asserted here: an
# encoding that is wrong by one digit produces no error anywhere, so the
# fixture has to arrive at the name the same way the firmware does.
hex_ip() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    printf '%02X%02X%02X%02X' "$a" "$b" "$c" "$d"
}

# The name a per-network file is written under: as many hex digits as the
# netmask covers, rounded up to a whole digit. A /24 is six digits, which is
# what a loader asks for after failing to find a file for its own address.
hex_net() {
    local ip=$1 prefix=$2
    hex_ip "$ip" | cut -c1-$(( (prefix + 3) / 4 ))
}

dashed_mac() { echo "$1" | tr ':' '-'; }

reverse_name() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo "$d.$c.$b.$a.in-addr.arpa"
}

# A port nothing answers on: one for the web server to be moved to, and one
# for the control half of P-39, which needs a port that demonstrably refuses.
# Ports already handed out are passed in so the two are never the same.
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

# Where the x86_64 genesis kernel lives, if mknb has ever been run here. The
# discovery artefacts and the second-nodeset case both need it and neither can
# create it: building genesis needs the xCAT-genesis-base package and several
# minutes, which is not something a test fixture should do to a machine.
genesis_kernel() { echo "$(tftpdir)/xcat/genesis.kernel.$NODE_ARCH"; }
have_genesis()   { [ -f "$(genesis_kernel)" ]; }

# --- what was changed, so teardown is exact -------------------------------

# Every file the fixture creates is recorded as it is created, and teardown
# removes exactly those. A directory is recorded only if the fixture made it,
# so a tree that was already there survives.
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

# Start a daemon the suite needs and remember whether it was running, so a
# machine that had DNS switched off keeps it switched off afterwards.
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

# Being alive is not the same as being able to answer, and a daemon that is up
# with no socket makes every scenario fail on a timeout -- which reads as an
# xCAT fault and is not one. So each stage asks who holds its port first.
# Whether anything at all holds a port, which is a different question from
# which unit is active: on a management node the daemon behind a port is
# whatever the administrator chose, and the fixture only cares that the port
# answers.
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

dns_unit() {
    local unit
    for unit in named.service bind9.service named-chroot.service; do
        systemctl list-unit-files "$unit" >/dev/null 2>&1 && { echo "$unit"; return 0; }
    done
    return 1
}

http_unit() {
    local unit
    for unit in httpd.service apache2.service; do
        systemctl list-unit-files "$unit" >/dev/null 2>&1 && { echo "$unit"; return 0; }
    done
    return 1
}

tftp_unit() {
    local unit
    for unit in tftp.socket tftpd-hpa.service xinetd.service; do
        systemctl list-unit-files "$unit" >/dev/null 2>&1 && { echo "$unit"; return 0; }
    done
    return 1
}

# --- check ----------------------------------------------------------------

do_check() {
    local leftover
    [ "$(id -u)" = 0 ] || skip "the wire cases bind source addresses and low ports, which needs root"
    command -v ip >/dev/null 2>&1 || skip "iproute2 is not installed"
    command -v nodeset >/dev/null 2>&1 || skip "nodeset is not on PATH, so this is not a management node"
    command -v makedns >/dev/null 2>&1 || skip "makedns is not on PATH, so this is not a management node"
    # -f rather than -x: the fixture runs it as `python3 src/provtest`, so the
    # execute bit is only needed by whoever calls it directly, and dh_install
    # keeps the source mode on Debian.
    [ -f "$PROVTEST/src/provtest" ] || skip "provtest is not installed under $PROVTEST"

    # The clients the scenarios are driven with. They are real binaries on
    # purpose: a node fetches with the same ones.
    command -v dig >/dev/null 2>&1 || skip "dig is not installed (bind-utils / dnsutils)"
    command -v curl >/dev/null 2>&1 || skip "curl is not installed"
    command -v tftp >/dev/null 2>&1 || skip "a tftp client is not installed (tftp / tftp-hpa)"

    ip link add "${IF_SRV}probe" type veth peer name "${IF_CLI}probe" 2>/dev/null \
        || skip "this kernel has no veth support"
    ip link del "${IF_SRV}probe" 2>/dev/null

    # Nothing below is a missing feature: it is this machine already using
    # something the fixture would take over. Refusing is the only safe answer,
    # because the alternative is restoring somebody else's configuration from
    # a copy of it that was never theirs.
    ip -o addr show | grep -qw "$SRV_IP" && skip "$SRV_IP is already configured on this machine"
    ip link show "$IF_SRV" >/dev/null 2>&1 && skip "$IF_SRV already exists"
    ip netns list 2>/dev/null | grep -qw "$NETNS" && skip "a network namespace called $NETNS already exists"
    # Every name, not just $NODE: a teardown that stopped half way leaves some
    # of them behind, and checking only the first one defined would let setup
    # run again and record the leftovers as the configuration to restore to.
    for leftover in "$NODE" "$PXE_NODE" "$BOOT_NODE" "$XNBA_NODE" "$PTB_NODE" \
                    "$MASTER_NODE"; do
        lsdef "$leftover" >/dev/null 2>&1 \
            && skip "a node called $leftover is already defined"
    done
    lsdef -t network -o "$NETOBJ" >/dev/null 2>&1 && skip "a network called $NETOBJ is already defined"
    [ -d "$(pkgdir_for $NODE_ARCH)" ] && skip "$(pkgdir_for $NODE_ARCH) already exists"

    # P-43 is about a network xCAT does not manage. If this machine happens to
    # manage it, the scenario would be asserting the opposite of what it says.
    lsdef -t network -i net -c 2>/dev/null | grep -q "net=$FOREIGN_NET\$" \
        && skip "$FOREIGN_NET is a managed network here, so the foreign-address case cannot be run"

    say "environment is able to run the wire cases"
}

# --- setup ----------------------------------------------------------------

# A minimal install tree: the four files the install path actually fetches.
#
# It is fabricated rather than copied from a real distribution because what is
# under test is whether xCAT serves and names what it was told about, not
# whether a distribution installs. The files are small and their contents are
# never parsed by anything -- only fetched, sized and hashed.
fabricate_tree() {
    local arch=$1 dir images
    dir=$(pkgdir_for "$arch")

    # Where each architecture's installation media keeps its kernel, because
    # that is where xCAT looks: anaconda.pm reads images/pxeboot for x86_64 and
    # ppc/<arch> for the Power builds, and a tree without one refuses to
    # generate at all (anaconda.pm:1402, anaconda.pm:167).
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
    # What P-36 fetches: the node is told a repository URL and the URL has to
    # answer. repomd.xml is the first file any installer asks a repository for.
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

# The template mkinstall renders into /install/autoinst/<node>. It has to be a
# template xCAT will substitute into rather than a finished file, because P-35
# fetches the *rendered* result from the URL the node was handed.
fabricate_template() {
    local path=$1
    write_file "$path" <<'EOF'
# provtest kickstart template. Rendered by mkinstall into
# /install/autoinst/<node>; fetched over HTTP by the wire cases and by nothing
# else. It is a valid-enough kickstart to be rendered, and is never installed.
install
text
reboot
rootpw --iscrypted *
%post
#XCAT_KICKSTART_POST__
%end
EOF
}

# The grub2 network loader.
#
# xCAT does not build this and never has: grub2.pm refuses to write a node's
# config at all if it is missing (grub2.pm:309-311), and the administrator is
# expected to have put it there. So the fixture stands in for the
# administrator -- it builds a real loader with the distribution's own
# grub2-mkimage, not a placeholder, because P-09 asserts a node can fetch it
# and a node that fetched an empty file would stop at the firmware.
#
# Where the modules are not installed there is nothing to build from, and the
# grub2 stage says so rather than inventing one.
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

# Move the web server to a port the cluster does not use yet. The alias
# definitions in xcat.conf are server-wide, so one Listen line is the whole of
# what changing site.httpport requires -- but only Apache reads that directory,
# and only if it can be restarted at all, so this is attempted and not assumed.
# Everything it wrote is undone when it cannot be made to answer, because a
# half-moved web server is worse than one that never moved.
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
    # Restarted rather than started: the Listen line is read at startup, and a
    # server that was already running has not read it.
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

    # Everything that gets changed is recorded first, so teardown is exact
    # rather than a guess at what the defaults used to be.
    tabdump site > "$STATE/site.csv" || die "cannot read the site table"
    cp -f /etc/hosts "$STATE/hosts" || die "cannot save /etc/hosts"
    save_dns_config

    ip link add "$IF_SRV" type veth peer name "$IF_CLI" || die "cannot create the veth pair"
    echo done > "$STATE/veth"
    ip addr add "$SRV_IP/$PREFIX" dev "$IF_SRV" || die "cannot address $IF_SRV"
    ip link set "$IF_SRV" up || die "cannot bring up $IF_SRV"

    # The foreign network is reached through a gateway rather than being put on
    # this interface, and the distinction is the whole test: xcatd asks
    # NetworkUtils::nodeonmynet whether a discovering address is one of ours,
    # and that reads the routing table and counts only the directly attached
    # routes. An address the management node can reach but is not on the wire
    # with is exactly the case P-43 is about, and giving $IF_SRV an address in
    # that network would quietly turn the foreign client into a local one.
    ip route add "$FOREIGN_NET/$PREFIX" via "$NODE_IP" dev "$IF_SRV" \
        || die "cannot route $FOREIGN_NET/$PREFIX through $NODE_IP"

    # The client end lives in a namespace of its own, and that is not a tidiness
    # measure: xcatd calls a discovering machine back on TCP 3001, the same port
    # it listens on itself, so a client sharing the management node's network
    # stack can never hold the port the callback is addressed to. In a namespace
    # it can, and the rest of the chain is unchanged -- the packets still cross
    # a real wire, and xcatd still sees them arrive from the node's address.
    ip netns add "$NETNS" || die "cannot create the network namespace $NETNS"
    echo done > "$STATE/netns"
    ip link set "$IF_CLI" netns "$NETNS" || die "cannot move $IF_CLI into $NETNS"

    # The client end holds the node's address, the unknown address and the
    # foreign one. Which of the three a request leaves by is the only thing
    # that distinguishes the scenarios that use them.
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

    # The discovery worker reads the routing table once and keeps it for the
    # life of the process (NetworkUtils::nodeonmynet caches per pid), so a
    # daemon that was running before the veth and the foreign route were made
    # decides P-43 against a table that no longer exists. Restarting it here
    # costs a few seconds and makes the answer depend on the fixture rather
    # than on how long xcatd has been up.
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

    # The daemons a node fetches from. Started before anything is generated,
    # because whether the web server can be moved to another port decides what
    # site.httpport is set to, and site.httpport is read by the plugins that
    # write the node's boot configuration.
    # A port that is already held needs no unit started: a management node runs
    # whichever daemon its administrator installed, and some of them are not
    # under a unit at all -- xcatconfig starts in.tftpd itself.
    serving udp 53 || { dns=$(dns_unit)   && ensure_running "$dns";  } \
        || say "no DNS unit was started; the DNS stage will say so"
    serving udp 69 || { tftp=$(tftp_unit) && ensure_running "$tftp"; } \
        || say "no TFTP unit was started; the TFTP stage will say so"

    # site.master is what lands on a kernel command line as xcatd=<addr>:3001,
    # and site.domain is the zone makedns writes. Both are restored wholesale
    # from site.csv by teardown, unset included.
    chdef -t site -o clustersite master="$SRV_IP" domain="$DOMAIN" \
        || die "cannot set site.master and site.domain"

    # site.httpport is moved only if the move takes: a cluster whose web server
    # the fixture cannot reconfigure keeps the port it has, and the HTTP stage
    # asserts the half of P-39 that applies to it.
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

    # hostnames= is what becomes the CNAME P-04 asks for: makehosts writes the
    # alias alongside the node in /etc/hosts and makedns turns it into a record.
    define_node "$NODE" "$NODE_IP" "$NODE_MAC" "$NODE_ARCH" "$NODE_NETBOOT" \
        "$OSIMAGE" hostnames="$ALIAS"
    define_node "$PXE_NODE" "$PXE_IP" "$PXE_MAC" "$NODE_ARCH" pxe "$OSIMAGE"
    define_node "$BOOT_NODE" "$BOOT_IP" "$BOOT_MAC" "$NODE_ARCH" pxe "$OSIMAGE"
    define_node "$XNBA_NODE" "$XNBA_IP" "$XNBA_MAC" "$NODE_ARCH" xnba "$OSIMAGE"
    define_node "$PTB_NODE" "$PTB_IP" "$PTB_MAC" "$PTB_ARCH" petitboot "$PTB_OSIMAGE"

    # The master gets a definition of its own so that P-07 has a name to
    # resolve. It is never provisioned and never nodeset.
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
    # The zone files themselves, as a whole tree: makedns rewrites and removes
    # inside it, and restoring file by file would miss the removals.
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

# The file a node of each netboot type is given, by the name the loader asks
# for it by. This is the fixture's own arithmetic and not a question put to
# xCAT: the point of the suite is that the two agree.
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

# Generate the artefacts: the ones a node fetches, and the records that decide
# whose they are. Separate from setup so run-ordering can regenerate after
# changing exactly one thing.
#
# nodeset is run for the files it writes and not for the status it exits with.
# It reports a DHCP backend that is not running as a failure of the whole
# command, having already written every boot configuration, and the DHCP wire
# is a different suite's subject; so each artefact is looked for by name.
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

    # The ppc64le node is set separately: its osimage is a different one, and
    # on a management node that cannot generate for another architecture the
    # petitboot stage says so rather than the whole setup failing.
    nodeset "$PTB_NODE" osimage="$PTB_OSIMAGE" >/dev/null 2>&1
    generated petitboot "$PTB_NODE" "$PTB_IP" \
        || say "no petitboot configuration was written for $PTB_NODE; the petitboot stage will say so"

    nodeset "$BOOT_NODE" boot >/dev/null 2>&1
    generated pxe "$BOOT_NODE" "$BOOT_IP" \
        || die "nodeset $BOOT_NODE boot wrote no configuration for $BOOT_NODE"

    # The per-network discovery configurations name every network xCAT knows,
    # so the fixture's network only appears in them once mknb has run again.
    # `-c` writes those files from the genesis images already under $tftpdir
    # and rebuilds nothing, which is why this is affordable in a fixture.
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

# Everything a node does is done from the node's namespace, so the source
# address, the ports that are free, and the routes are the node's own.
in_ns() { ip netns exec "$NETNS" "$@"; }

provtest_run() {
    ( cd "$PROVTEST" && in_ns python3 src/provtest run "$@" )
}

common_set() {
    echo "--set server=$SRV_IP --set client=$NODE_IP"
}

# Stage 1. The forwarded-name scenario is selected separately because it needs
# a working forwarder, which is a fact about the runner's network and not about
# xCAT: reporting "no internet" as a DNS fault would make the whole file
# untrustworthy.
do_run_dns() {
    local rc=0 scenarios
    assert_serving udp 53 "the name server"

    scenarios="-s node-forward -s node-reverse -s node-alias -s local-nxdomain -s master-resolves"
    provtest_run $scenarios \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set domain="$DOMAIN" \
        --set nodeip="$NODE_IP" --set revname="$(reverse_name "$NODE_IP")" \
        --set alias="$ALIAS" --set master="$MASTER_NODE.$DOMAIN" \
        --set missing="$MISSING" --set forwarded="$FORWARDED" \
        --set net="$NET/$PREFIX" \
        conf/dns.conf || rc=1

    if dig +short +time=5 +tries=1 "$FORWARDED" A >/dev/null 2>&1 && \
       [ -n "$(dig +short +time=5 +tries=1 "$FORWARDED" A 2>/dev/null)" ]; then
        provtest_run -s forwarded-name \
            --set server="$SRV_IP" --set client="$NODE_IP" \
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
# attribute of the node, so a single node cannot answer for all four.
do_run_tftp() {
    local rc=0 loader tftp scenarios
    assert_serving udp 69 "the TFTP server"
    tftp=$(tftpdir)

    # The loader itself is not something the fixture can create: it is unpacked
    # from a package or built by copycds. Where it is absent the two scenarios
    # that fetch it are left out, rather than being satisfied with a placeholder
    # the fixture wrote -- which would assert that the fixture can create files.
    loader="boot/grub2/grub2.$NODE_ARCH"
    if [ -f "$tftp/$loader" ]; then
        scenarios=""
    else
        scenarios="-s grub2-node-config -s grub2-config-by-mac -s grub2-kernel-and-initrd -s tftp-escape"
        stage_skip "$tftp/$loader is not present, so the loader fetches are left out"
    fi
    provtest_run $scenarios \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")" \
        --set macdashes="$(dashed_mac "$NODE_MAC")" --set mac="$NODE_MAC" \
        --set loader="$loader" --set bootfile="$loader" \
        --set master="$SRV_IP" --set xcatport="$XCATPORT" --set destiny="$DESTINY" \
        conf/tftp-grub2.conf || rc=1

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$PXE_NODE" --set hexip="$(hex_ip "$PXE_IP")" \
        --set master="$SRV_IP" --set xcatport="$XCATPORT" --set destiny="$DESTINY" \
        --set bootnode="$BOOT_NODE" \
        conf/tftp-pxelinux.conf || rc=1

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$XNBA_NODE" --set httpport="$(httpport)" \
        conf/tftp-xnba.conf || rc=1

    if [ -f "$tftp/petitboot/$PTB_NODE" ]; then
        provtest_run \
            --set server="$SRV_IP" --set client="$NODE_IP" \
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
    other=$(free_port "$port") || die "no port is free for the control half of the port case"

    # P-39 has two halves and a cluster is on one side of it or the other: a
    # node is told a port, or told none and expected to use the default. Which
    # one is asserted follows from the port the cluster is actually on.
    select="-s install-tree -s tftp-tree-over-http -s urls-the-node-was-given"
    select="$select -s outside-the-aliases -s postscripts-listing"
    if [ "$port" = 80 ]; then
        select="$select -s default-port-the-node-was-told"
    else
        select="$select -s port-the-node-was-told"
    fi

    # shellcheck disable=SC2086
    provtest_run $select \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set httpport="$port" --set otherport="$other" \
        --set hexip="$(hex_ip "$NODE_IP")" \
        --set knownfile="boot/grub2/grub.cfg-$(hex_ip "$NODE_IP")" \
        --set installpath="autoinst/$NODE" \
        --set repofile="repodata/repomd.xml" \
        conf/http.conf
}

# Stage 5. The per-network artefacts, which only exist once genesis has been
# built: they are what a machine with no definition boots, and the fixture
# cannot create them without running mknb.
do_run_genesis() {
    local tftp hexnet select=""
    have_genesis || { stage_skip "genesis has not been built here ($(genesis_kernel) is missing); run mknb $NODE_ARCH"; return 0; }
    tftp=$(tftpdir); hexnet=$(hex_net "$NET" "$PREFIX")

    # One scenario per loader family, and only the families this architecture
    # is actually given: mknb writes a grub2 per-network configuration for the
    # UEFI architectures and pxelinux and xnba ones for x86_64. Selecting them
    # by name means a family that is not written is absent from the report
    # rather than passing vacuously.
    [ -e "$tftp/pxelinux.cfg/$hexnet" ] &&
        select="$select -s pxelinux-discovery-config -s genesis-images-pxelinux"
    [ -e "$tftp/xcat/xnba/nets/$NET_FILE" ] &&
        select="$select -s xnba-discovery-config"
    [ -e "$tftp/boot/grub2/grub.cfg-$hexnet" ] &&
        select="$select -s grub2-discovery-config -s genesis-images-grub2"

    [ -n "$select" ] || { stage_skip "mknb has written no configuration for $NET/$PREFIX, so there is nothing a machine without a definition would fetch"; return 0; }
    assert_serving udp 69 "the TFTP server"

    # Unquoted on purpose: the selection is a list of options this script built
    # itself, and there is nothing in it a word split can damage.
    # shellcheck disable=SC2086
    provtest_run $select \
        --set server="$SRV_IP" --set client="$NODE_IP" \
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
        --set server="$SRV_IP" --set client="$NODE_IP" \
        conf/flowcontrol.conf || rc=1

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set foreign="$FOREIGN_IP" \
        conf/findme.conf || rc=1
    return $rc
}

# Stages 9 to 12. The order is the order a node does them in, and it matters:
# chain-advances calls nextdestiny, which moves the node off `install`, so
# everything that asserts destiny=install has to have run already.
do_run_xcatd() {
    local rc=0
    assert_serving tcp "$XCATPORT" "xcatd"

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set xcatport="$XCATPORT" --set refused=rpower --set node="$NODE" \
        conf/xcatd-policy.conf || rc=1

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set unknown="$UNKNOWN_IP" --set node="$NODE" \
        --set xcatport="$XCATPORT" --set monitorport="$MONITORPORT" \
        conf/xcatd-postscript.conf || rc=1

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set xcatport="$XCATPORT" --set credtype=xcat_server_cred \
        conf/xcatd-credentials.conf || rc=1

    # Last, and after the node has been put back into its starting state,
    # because these scenarios end by advancing the chain: nextdestiny is not a
    # question, it is a write, and a second run of this stage against the node
    # it left behind would be asserting install against a node that is now set
    # to boot. Resetting here is what makes the stage repeatable.
    nodeset "$NODE" osimage="$OSIMAGE" >/dev/null 2>&1
    generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
        || die "nodeset wrote no $NODE_NETBOOT configuration for $NODE"

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set unknown="$UNKNOWN_IP" --set node="$NODE" \
        --set destiny="$DESTINY" --set master="$SRV_IP" --set xcatport="$XCATPORT" \
        conf/xcatd-destiny.conf || rc=1
    return $rc
}

# Stage 13.
do_run_monitor() {
    assert_serving tcp "$MONITORPORT" "the xcatd install monitor"

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set unknown="$UNKNOWN_IP" --set monitorport="$MONITORPORT" \
        --set xcatport="$XCATPORT" \
        conf/monitor.conf
}

# Failing at exactly one place. Each scenario needs the cluster in a different
# state, so the fixture drives them in order and selects them by name rather
# than running the file whole.
do_run_ordering() {
    local rc=0
    assert_serving tcp "$XCATPORT" "xcatd"

    # This stage ends by withdrawing the node's name, and everything before
    # that needs it back: nodeset resolves the node to name the config it
    # writes. Putting it back here rather than in teardown is what lets the
    # stage be run twice.
    if [ -f "$STATE/ptrgone" ]; then
        makehosts "$NODE" >/dev/null 2>&1 || say "makehosts $NODE reported an error"
        makedns -n >/dev/null 2>&1 || say "makedns -n reported an error"
        rm -f "$STATE/ptrgone"
    fi

    # Back to the starting state: the xcatd stage ends with a nextdestiny, and
    # P-74 is about a node that is still set to install being told to discover
    # itself anyway. Against a node already set to boot it would assert
    # nothing.
    nodeset "$NODE" osimage="$OSIMAGE" >/dev/null 2>&1
    generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
        || die "nodeset wrote no $NODE_NETBOOT configuration for $NODE"

    provtest_run -s unreachable-master \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")" \
        --set xcatport="$XCATPORT" --set unreachable="$UNREACHABLE_IP" \
        --set master="$SRV_IP" \
        --set destiny="$DESTINY" --set second="$SECOND_DESTINY" \
        conf/ordering.conf || rc=1

    # P-75 before P-74, and the order is forced rather than chosen: the second
    # nodeset has to resolve the node to write a config named after its
    # address, so it cannot run once the name has been withdrawn. P-74 is
    # therefore last, which is also where the DNS-removal stage picks up.
    #
    # P-75 itself: a second nodeset, to a state whose name the config has to
    # carry in place of the first one's.
    if have_genesis; then
        nodeset "$NODE" "$SECOND_DESTINY" >/dev/null 2>&1
        generated "$NODE_NETBOOT" "$NODE" "$NODE_IP" \
            || die "nodeset $NODE $SECOND_DESTINY wrote no $NODE_NETBOOT configuration"
        provtest_run -s state-replaced \
            --set server="$SRV_IP" --set client="$NODE_IP" \
            --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")" \
            --set xcatport="$XCATPORT" --set unreachable="$UNREACHABLE_IP" \
            --set master="$SRV_IP" \
            --set destiny="$DESTINY" --set second="$SECOND_DESTINY" \
            conf/ordering.conf || rc=1
    else
        stage_skip "genesis has not been built here, so there is no second state to set"
    fi

    # P-74: the node's name taken out of resolution, nothing else. It is still
    # defined, still set to install, still on the same address.
    #
    # Both the zone and /etc/hosts, because xcatd resolves the client address
    # with gethostbyaddr and that goes through nsswitch: with the hosts entry
    # left in place the name still resolves, the record removal is invisible,
    # and the scenario would pass by not being run. /etc/hosts is saved whole
    # at setup and restored whole at teardown.
    makedns -d "$NODE" >/dev/null 2>&1 || say "makedns -d $NODE reported an error"
    makehosts -d "$NODE" >/dev/null 2>&1 || say "makehosts -d $NODE reported an error"
    echo done > "$STATE/ptrgone"
    provtest_run -s missing-ptr \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set hexip="$(hex_ip "$NODE_IP")" \
        --set xcatport="$XCATPORT" --set unreachable="$UNREACHABLE_IP" \
        --set master="$SRV_IP" \
        --set destiny="$DESTINY" --set second="$SECOND_DESTINY" \
        conf/ordering.conf || rc=1

    return $rc
}

# What a withdrawn node must stop resolving to. Run last and on its own: it
# asserts the opposite of the DNS stage about the same names.
do_run_dns_removal() {
    assert_serving udp 53 "the name server"

    makedns -d "$NODE" >/dev/null 2>&1 || say "makedns -d $NODE reported an error"
    echo done > "$STATE/ptrgone"

    provtest_run \
        --set server="$SRV_IP" --set client="$NODE_IP" \
        --set node="$NODE" --set domain="$DOMAIN" \
        --set revname="$(reverse_name "$NODE_IP")" \
        conf/dns-removal.conf
}

# --- teardown -------------------------------------------------------------

do_teardown() {
    local name path dir
    [ -d "$STATE" ] || return 0

    # Every loop here reads its list on file descriptor 3 rather than on
    # standard input, because the xCAT clients inside them read standard input
    # themselves: on the first iteration the command swallows the rest of the
    # file, `read` sees end of file, and teardown stops after one name having
    # said it removed everything. That leaves nodes, a network object and a
    # rewritten site table behind, and the next setup records the leftovers as
    # the state to restore to.
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

    # What nodeset offline did not take with it.
    #
    # It is not reliable here: it exits as soon as it cannot reach the DHCP
    # backend -- which on a machine where these cases have just moved the DHCP
    # configuration about is likely -- and it leaves the kernel and initrd it
    # staged under the osimage name whatever happens. So the artefacts this
    # fixture's own nodes and images could have produced are removed by name.
    # Every name is the fixture's: a node it defined, an image it created, or
    # an address in the network it built, so nothing here can match a file the
    # machine had before.
    local tftp
    tftp=$(tftpdir)
    # Guarded, because the one recursive removal in this fixture must not be
    # able to become the whole directory if a name ever arrives empty.
    for name in "$OSIMAGE" "$PTB_OSIMAGE"; do
        [ -n "$name" ] && rm -rf "$tftp/xcat/osimage/$name"
    done
    # One node produces several files, and not all of them are named after it
    # plainly: xnba writes .uefi and .elilo beside the script, and grub2 writes
    # both <node> and grub2-<node> beside the hex-IP config. The globs are
    # anchored on a node name this fixture defined, so they cannot reach
    # anything else.
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
    # And the per-network ones, which mknb writes for the discovery stage. The
    # xnba form is named after the network and its prefix rather than in hex.
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
    # with it, and deleting the server end afterwards takes the rest.
    [ -f "$STATE/netns" ] && ip netns del "$NETNS" >/dev/null 2>&1
    [ -f "$STATE/veth" ] && ip link del "$IF_SRV" >/dev/null 2>&1

    # tabrestore replaces the table wholesale, which is what is wanted here:
    # site.master and site.domain go back to exactly what they were, unset
    # included, rather than to a guess at the default.
    [ -f "$STATE/site.csv" ] && tabrestore "$STATE/site.csv" >/dev/null 2>&1
    [ -f "$STATE/hosts" ] && cp -f "$STATE/hosts" /etc/hosts

    restore_dns_config
    # The records are regenerated from the restored configuration, so a machine
    # that was serving its own zones is serving them again and not a copy of
    # them with the fixture's node still in it.
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
