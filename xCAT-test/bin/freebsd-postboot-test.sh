#!/bin/sh

# Run in a disposable native guest; each case uses its own chroot.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -ge 2 ] && [ "$#" -le 3 ]
workspace=$1
source=$2
selection=${3:-all}
case "$selection" in all|terminal|lifecycle) ;; *) exit 2 ;; esac
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
root=$workspace/root
mkdir -m 0755 "$root"
mkdir -p "$root/dev" "$root/etc/defaults" "$root/etc/rc.d" "$root/var/run" "$root/var/db/xcat" \
    "$root/usr/local/libexec" "$root/usr/local/etc/rc.d"
chmod 0700 "$root/var/db/xcat"
for tool in sh cat chmod cp date kill mkdir mv rm sleep test timeout ps hostname \
    sysctl sha256 awk base64 cmp env fsync grep head id kenv limits lockf logger mktemp \
    sed stat tail tr uname wc daemon; do
    path=$(command -v "$tool")
    case "$path" in /*) ;; *) path=/bin/$tool ;; esac
    printf '%s\n' "$path" >> "$workspace/paths"
    ldd "$path" >> "$workspace/ldd"
done
printf '%s\n' /libexec/ld-elf.so.1 >> "$workspace/paths"
awk '$2 == "=>" && $3 ~ /^\// {print $3}' "$workspace/ldd" >> "$workspace/paths"
! grep -q 'not found' "$workspace/ldd"
sort -u "$workspace/paths" > "$workspace/runtime"
while IFS= read -r path; do
    mkdir -p "$root$(dirname "$path")"
    cp -p "$path" "$root$path"
done < "$workspace/runtime"
cp -p /etc/rc.subr /etc/login.conf "$root/etc/"
: > "$root/etc/rc.conf"
cp -p /etc/defaults/rc.conf "$root/etc/defaults/"
install -m 0444 "$source/xcat-install-lib.sh" "$root/usr/local/libexec/xcat-install-lib.sh"
install -m 0555 "$source/xcat-postscript" "$root/usr/local/libexec/xcat-postscript"
install -m 0555 "$source/xcat-postscript-time" "$root/usr/local/libexec/xcat-postscript-time.real"
install -m 0555 "$source/xcat-postboot" "$root/usr/local/libexec/xcat-postboot"
install -m 0555 "$source/xcat-postboot" "$root/usr/local/etc/rc.d/xcatpostboot"
/bin/sh -n "$root/usr/local/libexec/xcat-postboot"
mount -t devfs devfs "$root/dev"
finish()
{
    status=$?
    trap - EXIT
    chroot "$root" /usr/local/etc/rc.d/xcatpostboot onestop > "$workspace/cleanup.stdout" 2>&1 || :
    umount "$root/dev" || status=1
    printf '%s\n' "$status" > "$workspace/exit-code"
    exit "$status"
}
trap finish EXIT

mv "$root/bin/sleep" "$root/bin/sleep.real"
cat > "$root/bin/sleep" <<'SLEEP'
#!/bin/sh
clock=$(cat /clock)
monotonic=$(cat /monotonic)
step=1000
[ ! -e /wall-step ] || step=$(cat /wall-step)
printf '%s\n' "$((clock + step))" > /clock
printf '%s\n' "$((monotonic + 1000))" > /monotonic
SLEEP
cat > "$root/bin/date" <<'DATE'
#!/bin/sh
cat /clock
DATE
cat > "$root/usr/local/libexec/xcat-postscript-time" <<'TIMER'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = uptime ]; then cat /monotonic
else exec /usr/local/libexec/xcat-postscript-time.real "$@"; fi
TIMER
cat > "$root/usr/bin/nc" <<'NC'
#!/bin/sh
IFS= read -r request || exit 1
printf '%s\n' "$request" >> /requests
set -f
set -- $request
if [ -e /outage ]; then exit 1; fi
if [ "$1" = freebsd-install-v1 ]; then
    printf 'ready\nfreebsd-install-v1 %s booted ok\n' "$2"
    exit 0
fi
if [ -e /block ]; then
    : > /entered
    /bin/sleep.real 30
    exit 1
fi
count=$(cat /count)
count=$((count + 1))
printf '%s\n' "$count" > /count
if [ -e /reply.$count ]; then cat "/reply.$count"; else cat /reply; fi
NC
chmod 0555 "$root/bin/date" "$root/bin/sleep" "$root/usr/bin/nc"
chmod 0555 "$root/usr/local/libexec/xcat-postscript-time"
generation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
attempt=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
run=cccccccccccccccccccccccccccccccc
boot=$(chroot "$root" /usr/local/libexec/xcat-postscript boot-identity)
record=$root/var/db/xcat/boot-report/$boot
config=$root/var/db/xcat/boot-controller
reporter=/usr/local/libexec/xcat-postboot

reset_case()
{
    label=$1
    case_dir=$workspace/$label
    mkdir -m 0700 "$case_dir"
    if [ -e "$root/var/db/xcat/boot-report" ]; then
        mv "$root/var/db/xcat/boot-report" "$workspace/previous-state"
        mv "$workspace/previous-state" "$previous/state"
    fi
    rm -f "$root/reply" "$root"/reply.* "$root/outage" "$root/block" "$root/entered" "$root/wall-step" "$config"
    printf '100000\n' > "$root/clock"
    printf '100000\n' > "$root/monotonic"
    printf '0\n' > "$root/count"
    : > "$root/requests"
    printf '192.0.2.1\n3002\n%s\n%s\n' "$generation" "$attempt" > "$config"
    chmod 0600 "$config"
    reply success
    previous=$case_dir
}

reply()
{
    response_result=$1
    identity=$run
    [ "$response_result" != disabled ] || identity=-
    printf 'ready\nfreebsd-install-postscripts-v1 %s %s %s %s\n' \
        "$generation" "$boot" "$identity" "$response_result" > "$root/reply"
}

invoke()
{
    expected=$1
    status=0
    chroot "$root" "$reporter" report > "$case_dir/stdout" 2> "$case_dir/stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/status"
    cp "$root/requests" "$case_dir/requests"
    [ "$status" -eq "$expected" ]
}

field()
{
    awk -F '\t' -v key="$1" '$1 == key {print $2}' "$record"
}

if [ "$selection" != lifecycle ]; then
for result in success failed uncertain disabled; do
    reset_case "$result"
    reply "$result"
    expected=0
    case "$result" in failed) expected=1 ;; uncertain) expected=2 ;; esac
    invoke "$expected"
    [ "$(field outcome)" = "$result" ]
    [ "$(field booted)" = yes ]
    [ "$(field boot)" = "$boot" ]
    [ "$(stat -f '%u:%g:%l:%Lp' "$record")" = 0:0:1:600 ]
    [ "$(wc -l < "$case_dir/requests" | tr -d ' ')" -eq 2 ]
    printf 'PASS terminal %s\n' "$result"
done
[ "$selection" != terminal ] || exit 0

reset_case retry
reply pending
cp "$root/reply" "$root/reply.1"
reply success
invoke 0
[ "$(field outcome)" = success ]
[ "$(cat "$root/count")" = 2 ]
tail -n 2 "$case_dir/requests" | uniq > "$case_dir/identities"
[ "$(wc -l < "$case_dir/identities" | tr -d ' ')" -eq 1 ]
printf 'PASS pending retry keeps boot identity\n'

for step in -20000 20000; do
    reset_case "clock-$step"
    printf '%s\n' "$step" > "$root/wall-step"
    reply pending
    cp "$root/reply" "$root/reply.1"
    reply success
    invoke 0
    [ "$(cat "$root/count")" = 2 ]
    [ "$(cat "$root/monotonic")" = 101000 ]
    [ "$(cat "$root/clock")" -eq "$((100000 + step))" ]
    [ "$(field outcome)" = success ]
    printf 'PASS wall-clock step %s preserves pending retry\n' "$step"
done

for bad in generation boot extra-line extra-field wrong-run malformed large pending; do
    reset_case "$bad"
    case "$bad" in
    generation) sed "s/$generation/$attempt/" "$root/reply" > "$root/reply.new"; mv "$root/reply.new" "$root/reply" ;;
    boot) sed "s/$boot/$(printf '%064d' 0)/" "$root/reply" > "$root/reply.new"; mv "$root/reply.new" "$root/reply" ;;
    extra-line) printf '\n' >> "$root/reply" ;;
    extra-field) printf 'ready\nfreebsd-install-postscripts-v1 %s %s %s success extra\n' "$generation" "$boot" "$run" > "$root/reply" ;;
    wrong-run) reply disabled; sed 's/ - disabled/ bad disabled/' "$root/reply" > "$root/reply.new"; mv "$root/reply.new" "$root/reply" ;;
    malformed) printf 'success\n' > "$root/reply" ;;
    large) dd if=/dev/zero of="$root/reply" bs=4096 count=2 2>/dev/null ;;
    pending) reply pending ;;
    esac
    invoke 1
    [ "$(field outcome)" = pending ]
    [ "$(field booted)" = yes ]
    printf 'PASS bounded %s\n' "$bad"
done

reset_case outage
: > "$root/outage"
invoke 1
[ "$(field booted)" = no ]
[ "$(field outcome)" = pending ]
cp "$record" "$case_dir/pending"
rm "$root/outage"
invoke 0
[ "$(field booted)" = yes ]
[ "$(field outcome)" = success ]
printf 'PASS controller outage retry\n'

for bad in config-mode config-link record-link; do
    reset_case "$bad"
    printf 'preserve\n' > "$root/sentinel"
    case "$bad" in
    config-mode) chmod 0644 "$config" ;;
    config-link) mv "$config" "$root/saved-config"; ln -s /saved-config "$config" ;;
    record-link) mkdir -m 0700 "$root/var/db/xcat/boot-report"; ln -s /sentinel "$record" ;;
    esac
    invoke 1
    [ ! -s "$case_dir/requests" ]
    [ "$(cat "$root/sentinel")" = preserve ]
    printf 'PASS protected %s\n' "$bad"
done
fi

reset_case lifecycle
: > "$root/block"
chroot "$root" /usr/local/etc/rc.d/xcatpostboot onestart > "$case_dir/start.stdout" 2> "$case_dir/start.stderr"
tries=0
while [ ! -e "$root/entered" ] && [ "$tries" -lt 50 ]; do /bin/sleep 0.1; tries=$((tries+1)); done
[ -e "$root/entered" ]
chroot "$root" /usr/local/etc/rc.d/xcatpostboot onestatus > "$case_dir/status.stdout" 2>&1
chroot "$root" /usr/local/etc/rc.d/xcatpostboot onestart > "$case_dir/restart.stdout" 2>&1 || :
status=0
chroot "$root" "$reporter" report > "$case_dir/duplicate.stdout" 2> "$case_dir/duplicate.stderr" || status=$?
[ "$status" -eq 75 ]
chroot "$root" /usr/local/etc/rc.d/xcatpostboot onestop > "$case_dir/stop.stdout" 2>&1
tries=0
while [ -e "$root/var/run/xcatpostboot.pid" ] && [ "$tries" -lt 50 ]; do
    /bin/sleep 0.1
    tries=$((tries+1))
done
[ ! -e "$root/var/run/xcatpostboot.pid" ]
[ "$(field outcome)" = pending ]
[ "$(wc -l < "$root/requests" | tr -d ' ')" -eq 2 ]
rm "$root/block"
invoke 0
[ "$(field outcome)" = success ]
[ ! -e "$root/var/db/xcat/postscripts" ]
mv "$root/var/db/xcat/boot-report" "$case_dir/state"
printf 'PASS native rc lifecycle, serialization and interrupted report retry\n'
