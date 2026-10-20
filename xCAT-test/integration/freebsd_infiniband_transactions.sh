#!/bin/sh
# Run on an explicitly selected disposable node with one managed static IB port.
set -efu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH
umask 077
[ "$(uname -s):$(id -u)" = FreeBSD:0 ] || exit 77
[ -n "${XCAT_FREEBSD_NETWORK_LAB_UUID:-}" ] || exit 77
[ "$(kenv -q smbios.system.uuid)" = "$XCAT_FREEBSD_NETWORK_LAB_UUID" ] || exit 1
nic=${XCAT_FREEBSD_NETWORK_LAB_NIC:?Select the managed IB port}
bootnic=${XCAT_FREEBSD_NETWORK_LAB_BOOTNIC:?Select the Ethernet installation interface}
printf '%s\n' "$nic" | awk '!/^ib[0-9]+$/ {exit 1}' || exit 1
case ${NICEXTRAPARAMS:-} in
*,*) exit 1 ;;
''|"$nic"!*) ;;
*) exit 1 ;;
esac
entry=$(CDPATH= cd -P "$(dirname "$0")/../../xCAT/postscripts" && pwd)/confignetwork
planner=${entry%/*}/confignetwork-freebsd.awk
state=/var/db/xcat/network
original_ifconfig=/sbin/ifconfig.xcat-infiniband-test
[ ! -e "$state/pending" ] && [ -f "$state/current" ] || exit 1
[ ! -e "$original_ifconfig" ] && [ ! -L "$original_ifconfig" ] || exit 1
[ -f /sbin/ifconfig ] && [ ! -L /sbin/ifconfig ] || exit 1
awk -F '\t' -v nic="$nic" '
    $1=="I" {n++; if ($2!=nic || $3!="infiniband") bad=1}
    $1=="H" || $1=="H6" {bad=1}
    END {exit (n!=1 || bad)}' "$state/current" || exit 1
for directory in /etc/rc.conf.d /usr/local/etc/rc.conf.d; do
    [ ! -L "$directory" ] && [ ! -e "$directory/kld" ] && [ ! -L "$directory/kld" ] || exit 1
done
work=$(mktemp -d /var/tmp/xcat-ib-transaction.XXXXXXXX)
printf '# Evidence: %s\n' "$work"
awk -v bootnic="$bootnic" -f "$planner" > "$work/compiled.plan"
cmp "$work/compiled.plan" "$state/current" || exit 1
cp -p /etc/rc.conf "$work/before.rc"
cp "$state/current" "$work/before.plan"
sha256 -q /sbin/ifconfig > "$work/ifconfig.sha256"
original_options=${NICEXTRAPARAMS:-}
created_directories=
active_override=
failures=0
cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ -e "$original_ifconfig" ]; then mv -f "$original_ifconfig" /sbin/ifconfig || result=1; fi
    if [ -n "$active_override" ]; then rm -f "$active_override" || result=1; fi
    for directory in $created_directories; do rmdir "$directory" || result=1; done
    if [ ! -e "$state/pending" ] && cmp -s "$state/current" "$work/before.plan"; then
        cp -p "$work/before.rc" /etc/rc.conf || result=1
        fsync /etc/rc.conf /etc || result=1
    else
        printf 'Bail out! Retain network recovery evidence in %s\n' "$work" >&2
        result=1
    fi
    sha256 -q /sbin/ifconfig > "$work/restored-ifconfig.sha256"
    cmp -s "$work/ifconfig.sha256" "$work/restored-ifconfig.sha256" || result=1
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
record()
{
    if [ "$1" = 0 ]; then printf 'ok %s - %s\n' "$2" "$3"
    else printf 'not ok %s - %s\n' "$2" "$3"; failures=$((failures+1)); fi
}
invoke()
{
    status=0
    "$entry" "$@" > "$work/$label.stdout" 2> "$work/$label.stderr" || status=$?
    [ ! -e "$state/pending" ] || exit 1
}
printf '1..5\n'
label=repeat
invoke --ibaports=1
if [ "$status" = 0 ] && grep -q 'configuration is unchanged' "$work/repeat.stdout"; then
    record 0 1 'legacy IB argument retains an unchanged configuration'
else record 1 1 'legacy IB argument retains an unchanged configuration'; fi

module=${XCAT_FREEBSD_NETWORK_LAB_MODULE:-smbus}
printf '%s\n' "$module" | awk '!/^[a-z][a-z0-9_]*$/ {exit 1}' || exit 1
case " $(sysrc -n kld_list) " in *" $module "*) exit 1 ;; esac
sysrc -q kld_list+="$module"
sysrc -n kld_list > "$work/added-modules"
cp -p /etc/rc.conf "$work/added-modules.rc"
label=modules
invoke
sysrc -n kld_list > "$work/retained-modules"
if [ "$status" = 0 ] && cmp -s "$work/added-modules" "$work/retained-modules" &&
    cmp -s "$work/added-modules.rc" /etc/rc.conf &&
    grep -q 'configuration is unchanged' "$work/modules.stdout"; then
    record 0 2 'sysrc additions inside the managed block are preserved'
else record 1 2 'sysrc additions inside the managed block are preserved'; fi
cp -p "$work/before.rc" /etc/rc.conf

override_failure=0
for directory in /etc/rc.conf.d /usr/local/etc/rc.conf.d; do
    if [ ! -d "$directory" ]; then
        mkdir "$directory"
        created_directories="$directory $created_directories"
    fi
    active_override=$directory/kld
    printf 'kld_list="%s"\n' "$module" > "$active_override"
    label=override
    invoke
    if [ "$status" != 1 ] || ! grep -q 'Module overrides require manual integration' "$work/override.stderr" ||
        ! cmp -s "$work/before.rc" /etc/rc.conf; then override_failure=1; fi
    rm "$active_override"
    active_override=
done
record "$override_failure" 3 'both kld service overrides reject before mutation'

# Simulate lost carrier at the kernel-command boundary; keep production code unchanged.
export XCAT_FREEBSD_NETWORK_LAB_NIC="$nic"
export XCAT_FREEBSD_NETWORK_LAB_LOG="$work/ifconfig-writes"
export XCAT_FREEBSD_NETWORK_LAB_READBACK="$work/ifconfig-readback"
cat > "$work/ifconfig-wrapper" <<'WRAPPER'
#!/bin/sh
original=/sbin/ifconfig.xcat-infiniband-test
if [ -z "${XCAT_FREEBSD_NETWORK_LAB_NIC:-}" ] || [ -z "${XCAT_FREEBSD_NETWORK_LAB_LOG:-}" ] ||
    [ -z "${XCAT_FREEBSD_NETWORK_LAB_READBACK:-}" ]; then exec "$original" "$@"; fi
if [ "$#" = 1 ] && [ "$1" = -a ]; then
    "$original" -a > "$XCAT_FREEBSD_NETWORK_LAB_READBACK" || exit 1
    awk -v nic="$XCAT_FREEBSD_NETWORK_LAB_NIC" '
        $1 == nic ":" {gsub(/,LOWER_UP/, "")} {print}' "$XCAT_FREEBSD_NETWORK_LAB_READBACK"
else
    if [ "$#" -gt 1 ]; then printf '%s\n' "$*" >> "$XCAT_FREEBSD_NETWORK_LAB_LOG"; fi
    exec "$original" "$@"
fi
WRAPPER
chmod 0555 "$work/ifconfig-wrapper"
mv /sbin/ifconfig "$original_ifconfig"
cp -p "$work/ifconfig-wrapper" /sbin/ifconfig
env -u XCAT_FREEBSD_NETWORK_LAB_READBACK ifconfig -a > "$work/external.kernel"
"$original_ifconfig" -a > "$work/expected.kernel"
cmp "$work/external.kernel" "$work/expected.kernel"
: > "$XCAT_FREEBSD_NETWORK_LAB_LOG"
label=carrier-unchanged
invoke
if [ "$status" = 0 ] && grep -q 'configuration is unchanged' "$work/$label.stdout" &&
    [ ! -s "$XCAT_FREEBSD_NETWORK_LAB_LOG" ] && cmp -s "$work/before.rc" /etc/rc.conf; then
    record 0 4 'unchanged policy during carrier loss does not reconfigure interfaces'
else record 1 4 'unchanged policy during carrier loss does not reconfigure interfaces'; fi

mtu=$(awk -F '\t' -v nic="$nic" '$1=="T" && $2==nic {print $3}' "$state/current")
[ "$mtu" -gt 1280 ] || exit 1
changed_mtu=$((mtu-1))
case "$original_options" in
*MTU=*) NICEXTRAPARAMS=$(printf '%s' "$original_options" | sed "s/MTU=[0-9]*/MTU=$changed_mtu/") ;;
'') NICEXTRAPARAMS="$nic!MTU=$changed_mtu" ;;
*) NICEXTRAPARAMS="$original_options MTU=$changed_mtu" ;;
esac
export NICEXTRAPARAMS
: > "$XCAT_FREEBSD_NETWORK_LAB_LOG"
label=carrier-changed
invoke
if [ "$status" = 1 ] && grep -q "InfiniBand link is not active: $nic" "$work/$label.stderr" &&
    [ ! -s "$XCAT_FREEBSD_NETWORK_LAB_LOG" ] && cmp -s "$work/before.rc" /etc/rc.conf; then
    record 0 5 'changed policy during carrier loss rejects before interface mutation'
else record 1 5 'changed policy during carrier loss rejects before interface mutation'; fi
NICEXTRAPARAMS=$original_options
mv -f "$original_ifconfig" /sbin/ifconfig
ifconfig -a > "$work/after.kernel"
netstat -rnW > "$work/after.routes"
awk -v mode=verify -f "$planner" "$work/before.plan" "$work/after.kernel"
awk -v mode=routes -f "$planner" "$work/before.plan" "$work/after.routes"
cmp "$work/before.plan" "$state/current"
[ "$failures" = 0 ]
