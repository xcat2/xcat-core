#!/bin/sh
# Run only on a disposable node whose saved plan matches the supplied postscript exports.
set -efu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH
umask 077

[ "$(uname -s)" = FreeBSD ] && [ "$(id -u)" = 0 ] || exit 77
[ -n "${XCAT_FREEBSD_NETWORK_LAB_UUID:-}" ] || exit 77
[ "$(kenv -q smbios.system.uuid)" = "$XCAT_FREEBSD_NETWORK_LAB_UUID" ] || exit 1
nic=${XCAT_FREEBSD_NETWORK_LAB_NIC:?Select an unused managed physical interface}
bootnic=${XCAT_FREEBSD_NETWORK_LAB_BOOTNIC:?Select the installation interface}
case "$nic:$bootnic" in *[!a-z0-9:]*|:*) exit 1 ;; esac
case ${XCAT_FREEBSD_NETWORK_LAB_SELECT:-} in ''|-s) ;; *) exit 1 ;; esac
adapter=$(CDPATH= cd -P "$(dirname "$0")/../../xCAT/postscripts" && pwd)/confignetwork
planner=${adapter%/*}/confignetwork-freebsd.awk
state=/var/db/xcat/network
[ -f "$state/current" ] && [ ! -e "$state/pending" ] || exit 1
awk -F '\t' -v nic="$nic" '
    $1 == "I" && $2 == nic && $3 == "ethernet" {found=1}
    $1 == "A" && $2 == nic {address=1}
    END {exit !(found && !address)}' "$state/current" || exit 1
case ,${NICEXTRAPARAMS:-}, in *,"$nic"!*) exit 1 ;; esac
if ifconfig lo99 >/dev/null 2>&1; then exit 1; fi
if ifconfig vlan3999 >/dev/null 2>&1; then exit 1; fi
if sysrc -n xcat_network_fixture >/dev/null 2>&1; then exit 1; fi
ROUTE_xcatfixture4=${XCAT_FREEBSD_NETWORK_LAB_ROUTE4:?Supply a disposable IPv4 route}
ROUTE_xcatfixture6=${XCAT_FREEBSD_NETWORK_LAB_ROUTE6:?Supply a disposable IPv6 route}
export ROUTE_xcatfixture4 ROUTE_xcatfixture6
work=$(mktemp -d /var/tmp/xcat-network-transaction.XXXXXXXX)
printf 'Evidence: %s\n' "$work"
cp -p /etc/rc.conf "$work/before.rc"
cp "$state/current" "$work/before.plan"
configure_boot=0
[ "${XCAT_FREEBSD_NETWORK_LAB_SELECT:-}" != -s ] || configure_boot=1
awk -v bootnic="$bootnic" -v configure_boot="$configure_boot" -f "$planner" > "$work/compiled.plan"
cmp -s "$work/compiled.plan" "$work/before.plan" || exit 1

apply()
{
    if [ "$configure_boot" = 1 ]; then "$adapter" -s; else "$adapter"; fi
}

fingerprint()
{
    sha256 -q /etc/rc.conf "$state/current"
    stat -f %m /etc/rc.conf
}

fingerprint > "$work/before.fingerprint"
original=${NICEXTRAPARAMS:-}
original_types=$NICTYPES
original_devices=${NICDEVICES:-}
original_routes=${NODEROUTENAMES:-}
route4=0
route6=0
clone=0
options=0
cleanup()
{
    status=$?
    trap - EXIT HUP INT TERM
    NICEXTRAPARAMS=$original
    NICTYPES=$original_types
    NICDEVICES=$original_devices
    NODEROUTENAMES=$original_routes
    export NICEXTRAPARAMS NICTYPES NICDEVICES NODEROUTENAMES
    if [ "$options" = 1 ]; then cp -p "$work/options.rc" /etc/rc.conf; fi
    if ! apply > "$work/restore.stdout" 2> "$work/restore.stderr"; then
        printf 'Bail out! Network restoration failed; retain %s\n' "$work"
        exit 1
    fi
    if [ "$route4" = 1 ]; then route -n delete -inet -net 203.0.113.0/24 127.0.0.1; fi
    if [ "$route6" = 1 ]; then route -n delete -inet6 -net 2001:db8:99::/64 ::1; fi
    if [ "$clone" = 1 ]; then ifconfig lo99 destroy; fi
    cp -p "$work/before.rc" /etc/rc.conf.network-test
    mv /etc/rc.conf.network-test /etc/rc.conf
    fsync /etc/rc.conf /etc
    fingerprint > "$work/after.fingerprint"
    cmp -s "$work/before.fingerprint" "$work/after.fingerprint" || exit 1
    [ ! -e "$state/pending" ] || exit 1
    exit "$status"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

printf '1..7\n'
sysrc -q xcat_network_fixture=YES
fingerprint > "$work/appended.fingerprint"
apply > "$work/appended.stdout" 2> "$work/appended.stderr"
grep -q 'configuration is unchanged' "$work/appended.stdout"
fingerprint > "$work/appended-after.fingerprint"
cmp -s "$work/appended.fingerprint" "$work/appended-after.fingerprint"
printf 'ok 1 - a setting after the managed block preserves the no-op\n'

route -n add -inet -net 203.0.113.0/24 127.0.0.1
route4=1
route -n add -inet6 -net 2001:db8:99::/64 ::1
route6=1
ifconfig lo99 create
clone=1
newline='
'
printf '%s="%s"\n' \
    static_routes "$(sysrc -n static_routes)${newline}xcat_network_fixture4" \
    ipv6_static_routes "$(sysrc -n ipv6_static_routes)${newline}xcat_network_fixture6" \
    cloned_interfaces "$(sysrc -n cloned_interfaces)${newline}lo99" > "$work/manual-lists.rc"
awk -v lists="$work/manual-lists.rc" '
    /^(static_routes|ipv6_static_routes|cloned_interfaces)=/ {next}
    $0 == "# END xCAT FreeBSD network" {
        while ((getline line < lists) > 0) print line
        close(lists)
    }
    {print}
' /etc/rc.conf > "$work/manual.rc"
cat "$work/manual.rc" > /etc/rc.conf
printf '%s="%s"\n' \
    route_xcat_network_fixture4 '-net 203.0.113.0/24 127.0.0.1' \
    ipv6_route_xcat_network_fixture6 '-net 2001:db8:99::/64 ::1' >> /etc/rc.conf
fingerprint > "$work/manual.fingerprint"
apply > "$work/manual.stdout" 2> "$work/manual.stderr"
grep -q 'configuration is unchanged' "$work/manual.stdout"
fingerprint > "$work/manual-after.fingerprint"
cmp -s "$work/manual.fingerprint" "$work/manual-after.fingerprint"
printf 'ok 2 - additions to effective route and clone lists remain unchanged\n'

NICEXTRAPARAMS=${original}${original:+,}$nic'!MTU=1400'
NICTYPES=$original_types',vlan3999!vlan'
NICDEVICES=${original_devices}${original_devices:+,}'vlan3999!'$nic
NODEROUTENAMES=${original_routes}${original_routes:+,}'xcatfixture4,xcatfixture6'
export NICEXTRAPARAMS NICTYPES NICDEVICES NODEROUTENAMES
apply > "$work/changed.stdout" 2> "$work/changed.stderr"
NICEXTRAPARAMS=$original
NICTYPES=$original_types
NICDEVICES=$original_devices
NODEROUTENAMES=$original_routes
export NICEXTRAPARAMS NICTYPES NICDEVICES NODEROUTENAMES
grep -q 'configuration applied and saved' "$work/changed.stdout"
ifconfig "$nic" | grep -q 'mtu 1400'
sysrc -n static_routes | grep -wq xcat_network_fixture4
sysrc -n ipv6_static_routes | grep -wq xcat_network_fixture6
sysrc -n cloned_interfaces | grep -wq lo99
ifconfig lo99 > "$work/manual-clone"
route -n get -inet 203.0.113.1 > "$work/manual-route4"
route -n get -inet6 2001:db8:99::1 > "$work/manual-route6"
printf 'ok 3 - an actual transaction preserves unmanaged routes and clones\n'

apply > "$work/reverted.stdout" 2> "$work/reverted.stderr"
cmp -s "$state/current" "$work/before.plan"
sysrc -n static_routes | grep -wq xcat_network_fixture4
sysrc -n ipv6_static_routes | grep -wq xcat_network_fixture6
sysrc -n cloned_interfaces | grep -wq lo99
printf 'ok 4 - reverting the managed plan preserves the manual additions\n'

cp -p /etc/rc.conf "$work/options.rc"
options=1
for setting in "ifconfig_$nic=up${newline}-lro -tso" "ifconfig_${nic}_ipv6=inet6 ifdisabled -auto_linklocal" \
    "ifconfig_${nic}_alias0=inet 198.19.0.2/24 fib 1"; do
    printf '%s="%s"\n' "${setting%%=*}" "${setting#*=}" >> /etc/rc.conf
    fingerprint > "$work/options-before.fingerprint"
    status=0
    apply > "$work/options.stdout" 2> "$work/options.stderr" || status=$?
    fingerprint > "$work/options-after.fingerprint"
    cp -p "$work/options.rc" /etc/rc.conf
    [ "$status" = 1 ]
    grep -q 'Interface options require manual integration' "$work/options.stderr"
    if grep -q 'restoring the previous network configuration' "$work/options.stderr"; then exit 1; fi
    cmp -s "$work/options-before.fingerprint" "$work/options-after.fingerprint"
    [ ! -e "$state/pending" ]
done
printf 'ok 5 - existing interface options reject adoption before mutation\n'

for setting in 'ifconfig_DEFAULT=up -lro' "ipv6_ifconfig_$nic=2001:db8:99::2 prefixlen 64" \
    "ipv6_ifconfig_${nic}_alias0=2001:db8:99::3 prefixlen 64"; do
    printf '%s="%s"\n' "${setting%%=*}" "${setting#*=}" >> /etc/rc.conf
    case "$setting" in ifconfig_DEFAULT=*) printf '\nunset ifconfig_%s_ipv6\n' "$nic" >> /etc/rc.conf ;; esac
    fingerprint > "$work/options-before.fingerprint"
    status=0
    apply > "$work/options.stdout" 2> "$work/options.stderr" || status=$?
    fingerprint > "$work/options-after.fingerprint"
    cp -p "$work/options.rc" /etc/rc.conf
    [ "$status" = 1 ]
    grep -q 'Interface options require manual integration' "$work/options.stderr"
    if grep -q 'restoring the previous network configuration' "$work/options.stderr"; then exit 1; fi
    cmp -s "$work/options-before.fingerprint" "$work/options-after.fingerprint"
    [ ! -e "$state/pending" ]
done
printf 'ok 6 - IPv6 fallback and obsolete address settings require integration\n'

printf '%s="%s"\n' ifconfig_DEFAULT 'up -lro' "ifconfig_${nic}_ipv6" '' >> /etc/rc.conf
apply > "$work/empty-ipv6.stdout" 2> "$work/empty-ipv6.stderr"
[ "$(sysrc -n ifconfig_DEFAULT)" = 'up -lro' ]
cp -p "$work/options.rc" /etc/rc.conf
cmp -s "$state/current" "$work/before.plan"
[ ! -e "$state/pending" ]
printf 'ok 7 - an explicitly empty IPv6 setting suppresses the default fallback\n'
