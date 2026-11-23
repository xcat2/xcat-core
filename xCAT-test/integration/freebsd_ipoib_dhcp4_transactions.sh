#!/bin/sh
# Requires a disposable node and an isolated server with a fixed DHCP reservation.
set -efu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH
unset IFCONFIG_FORMAT
umask 077
[ "$(uname -s):$(id -u)" = FreeBSD:0 ] || exit 77
[ -n "${XCAT_FREEBSD_NETWORK_LAB_UUID:-}" ] || exit 77
[ "$(kenv -q smbios.system.uuid)" = "$XCAT_FREEBSD_NETWORK_LAB_UUID" ] || exit 1
nic=${XCAT_FREEBSD_NETWORK_LAB_NIC:?Select the managed IPoIB interface}
bootnic=${XCAT_FREEBSD_NETWORK_LAB_BOOTNIC:?Select the installation interface}
wrong=${XCAT_FREEBSD_NETWORK_LAB_WRONG_IPV4:?Supply a different reserved-policy address}
printf '%s\n' "$nic" | awk '!/^ib[0-9]+$/ {exit 1}'
entry=$(CDPATH= cd -P "$(dirname "$0")/../../xCAT/postscripts" && pwd)/confignetwork
planner=${entry%/*}/confignetwork-freebsd.awk
service=/usr/local/etc/rc.d/xcat_ipoib_dhcp4
state=/var/db/xcat/network
[ ! -e "$state/pending" ] && [ -f "$state/dhcp/$nic.lease" ] || exit 1
awk -F '\t' -v nic="$nic" '
    $1=="I" {interfaces++; if ($2!=nic || $3!="infiniband") bad=1}
    $1=="H" {leases++; if ($2!=nic || $5!="yes" || $6!="no") bad=1}
    $1=="H6" {bad=1}
    END {exit (bad || interfaces!=1 || leases!=1)}' "$state/current"
work=$(mktemp -d /var/tmp/xcat-ipoib-dhcp4.XXXXXXXX)
printf '# Evidence: %s\n' "$work"
awk -v bootnic="$bootnic" -f "$planner" > "$work/compiled.plan"
cmp "$work/compiled.plan" "$state/current"
cp -p /etc/rc.conf "$work/before.rc"
cp "$state/current" "$work/before.plan"
cp "$state/dhcp/$nic.lease" "$work/before.lease"
tab=$(printf '\t')
while IFS="$tab" read -r key value; do
    case "$key" in old_*) export "new_${key#old_}=$value" ;; *) exit 1 ;; esac
done < "$work/before.lease"
expected=$new_ip_address
[ "$wrong" != "$expected" ] || exit 1
original_options=$NICEXTRAPARAMS
original_ips=$NICIPS

ready()
{
    count=0
    while [ "$count" -lt 25 ]; do
        if [ -f "$state/dhcp/$nic.lease" ] &&
            ifconfig "$nic" | awk -v ip="$expected" '$1=="inet" && $2==ip {found=1} END {exit !found}'; then
            return 0
        fi
        count=$((count+1))
        sleep 1
    done
    return 1
}

absent()
{
    ifconfig "$nic" > "$work/absent.kernel"
    resolvconf -i > "$work/absent.resolver"
    [ ! -e "$state/dhcp/$nic.lease" ] &&
        awk '$1=="inet" {bad=1} END {exit bad}' "$work/absent.kernel" &&
        ! tr ' ' '\n' < "$work/absent.resolver" | grep -qx "$nic"
}

event()
{
    env interface="$nic" reason="$1" \
        new_classless_static_routes='0.0.0.0/0 192.0.2.1 198.51.100.0/24 192.0.2.1' "$service"
}

cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    NICEXTRAPARAMS=$original_options
    NICIPS=$original_ips
    export NICEXTRAPARAMS NICIPS
    unset new_ip_address new_subnet_mask new_broadcast_address new_routers
    unset new_static_routes new_classless_routes new_classless_static_routes
    unset new_domain_name new_domain_name_servers new_domain_search
    if [ -f "$work/saved.conf" ]; then
        cp -p "$work/saved.conf" "$state/dhcp/ipoib.conf" || result=1
    fi
    if [ -e "$state/pending" ]; then
        printf 'Bail out! Retain the pending transaction and %s\n' "$work" >&2
        exit 1
    fi
    if [ -f "$service" ]; then
        "$service" forcestop >> "$work/cleanup.log" 2>&1 || result=1
        "$service" forcestart >> "$work/cleanup.log" 2>&1 || result=1
        ready || result=1
    fi
    "$entry" >> "$work/cleanup.log" 2>&1 || result=1
    cmp -s "$work/before.rc" /etc/rc.conf || result=1
    cmp -s "$work/before.plan" "$state/current" || result=1
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
printf '1..13\n'
"$entry" > "$work/unchanged.log" 2>&1
grep -q 'configuration is unchanged' "$work/unchanged.log"
printf 'ok 1 - an active reserved lease preserves the unchanged configuration\n'

"$service" forcestop > "$work/stop.log" 2>&1
absent || exit 1
printf 'ok 2 - service stop removes the address, receipt and resolver source\n'

env interface="$nic" reason=BOUND /bin/sh "$state/dhclient-script" > "$work/native-bound.log" 2>&1
ready
/bin/sh "$state/dhclient-script" --expire "$nic" > "$work/native-expire.log" 2>&1
absent || exit 1
printf 'ok 3 - the native DHCP event and explicit expiry paths retain their behavior\n'

event BOUND > "$work/bound.log" 2>&1
ready
resolvconf -i | tr ' ' '\n' | grep -qx "$nic"
printf 'ok 4 - a valid classless-route event applies the reserved address and DNS\n'

status=0
env new_classless_static_routes='192.0.2.1/24 192.0.2.1' \
    interface="$nic" reason=RENEW "$service" > "$work/bad-route.log" 2>&1 || status=$?
[ "$status" = 1 ] || exit 1
absent || exit 1
env old_ip_address="$expected" old_subnet_mask="$new_subnet_mask" \
    old_classless_static_routes='0.0.0.0/0 192.0.2.1' \
    new_classless_static_routes='0.0.0.0/0 192.0.2.1' \
    interface="$nic" reason=RENEW "$service" > "$work/renew-after-rejection.log" 2>&1
ready
printf 'ok 5 - malformed routes reject and a later renewal restores the address\n'

event BOUND > "$work/rebound.log" 2>&1
status=0
env new_ip_address="$wrong" interface="$nic" reason=RENEW \
    "$service" > "$work/wrong-address.log" 2>&1 || status=$?
[ "$status" = 1 ] || exit 1
absent || exit 1
printf 'ok 6 - a different address rejects and removes the previous lease\n'

event BOUND > "$work/rebound-dns.log" 2>&1
status=0
env new_domain_name_servers='invalid' interface="$nic" reason=RENEW \
    "$service" > "$work/bad-dns.log" 2>&1 || status=$?
[ "$status" = 1 ] || exit 1
absent || exit 1
printf 'ok 7 - invalid DNS rejects and removes the previous lease\n'

event BOUND > "$work/before-nak.log" 2>&1
event NAK > "$work/nak.log" 2>&1
absent || exit 1
printf 'ok 8 - a server NAK removes the accepted lease\n'

mv "$state/dhcp/ipoib.conf" "$work/saved.conf"
status=0
"$service" forcestart > "$work/missing-config.log" 2>&1 || status=$?
[ "$status" != 0 ] || exit 1
if pgrep -x dhcpcd-ipoib >/dev/null; then exit 1; fi
status=0
"$entry" > "$work/missing-config-transaction.log" 2>&1 || status=$?
[ "$status" = 1 ] || exit 1
grep -q 'saved IPoIB DHCPv4 client configuration is missing or unsafe' "$work/missing-config-transaction.log"
cmp "$work/before.rc" /etc/rc.conf
[ ! -e "$state/pending" ] || exit 1
cp -p "$work/saved.conf" "$state/dhcp/ipoib.conf"
printf 'ok 9 - a missing client configuration rejects forced start and a transaction\n'

started=$(date +%s)
"$service" forcestart > "$work/restart.log" 2>&1
[ "$(($(date +%s)-started))" -lt 20 ] || exit 1
[ -f "$state/dhcp/$nic.lease" ] || exit 1
ifconfig "$nic" | awk -v ip="$expected" '$1=="inet" && $2==ip {found=1} END {exit !found}'
"$service" forcestatus >> "$work/restart.log" 2>&1
printf 'ok 10 - service start returns promptly after reacquiring its reservation\n'

NICEXTRAPARAMS="$nic!BOOTPROTO=static"
export NICEXTRAPARAMS
"$entry" > "$work/static.log" 2>&1
[ ! -e "$service" ] || exit 1
[ ! -e "$state/dhcp/$nic.lease" ] || exit 1
ifconfig "$nic" | awk -v ip="$expected" '$1=="inet" && $2==ip {found=1} END {exit !found}'
if pgrep -x dhcpcd-ipoib >/dev/null; then exit 1; fi
printf 'ok 11 - static migration retains the address and removes the client service\n'

NICEXTRAPARAMS=$original_options
export NICEXTRAPARAMS
"$entry" > "$work/dhcp.log" 2>&1
ready
cmp "$work/before.rc" /etc/rc.conf
cmp "$work/before.plan" "$state/current"
printf 'ok 12 - DHCP migration restores the original plan and reservation\n'

NICIPS="$nic!$wrong"
export NICIPS
status=0
"$entry" > "$work/rollback.log" 2>&1 || status=$?
NICIPS=$original_ips
export NICIPS
[ "$status" = 1 ] || exit 1
[ ! -e "$state/pending" ] || exit 1
grep -q 'restoring the previous network configuration' "$work/rollback.log"
ready
cmp "$work/before.rc" /etc/rc.conf
cmp "$work/before.plan" "$state/current"
printf 'ok 13 - a mismatched server reservation rolls back to the previous lease\n'
