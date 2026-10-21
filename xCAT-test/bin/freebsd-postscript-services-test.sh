#!/bin/sh

# Native file operations run in a chroot; service, DNS and sysrc are recorded boundaries.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
LC_ALL=C
export PATH LC_ALL
umask 022
[ "$#" -ge 3 ] && [ "$#" -le 4 ]
workspace=$1
logging=$2
remoteshell=$3
selection=${4:-all}
for path in "$workspace" "$logging" "$remoteshell"; do
    case "$path" in /*) ;; *) exit 2 ;; esac
    case "$path" in *[!A-Za-z0-9_./+-]*|*/../*|*/..) exit 2 ;; esac
done
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
name=setup
finish()
{
    result=$?
    trap - EXIT
    printf '%s\n' "$result" > "$workspace/exit-code"
    if [ "$result" -ne 0 ]; then printf 'FAIL %s\n' "$name"; fi
    exit "$result"
}
trap finish EXIT
root=$workspace/root
mkdir -p "$root/libexec" "$root/scripts" "$root/fixture" "$root/dev"
: > "$root/dev/null"
for utility in sh chmod chown cat mv rm awk mktemp stat cmp uname id fsync dirname; do
    path=$(command -v "$utility")
    mkdir -p "$root${path%/*}"
    install -m 0555 "$path" "$root$path"
    ldd "$path" > "$workspace/ldd-$utility"
    awk '$2 == "=>" && $3 ~ /^\// { print $3 }' "$workspace/ldd-$utility" |
    while IFS= read -r library; do
        mkdir -p "$root${library%/*}"
        if [ -e "$root$library" ]; then cmp "$library" "$root$library"
        else install -m 0555 "$library" "$root$library"; fi
    done
done
install -m 0555 /libexec/ld-elf.so.1 "$root/libexec/ld-elf.so.1"
cp -p "$logging" "$root/scripts/syslog"
cp -p "$remoteshell" "$root/scripts/remoteshell"
chmod 0555 "$root/scripts/syslog" "$root/scripts/remoteshell"
for path in "$logging.freebsd" "$remoteshell.freebsd"; do
    if [ -f "$path" ]; then
        cp -p "$path" "$root/scripts/${path##*/}"
        chmod 0555 "$root/scripts/${path##*/}"
    fi
done
cat > "$root/usr/sbin/sysrc" <<'EOF'
#!/bin/sh
set -eu
if [ "$*" = '-n syslogd_flags' ]; then cat /fixture/flags; exit; fi
printf 'sysrc %s\n' "$*" >> /fixture/events
[ ! -e /fixture/enable-fail ] || exit 7
case "$*" in syslogd_enable=YES|sshd_enable=YES) ;; *) exit 99 ;; esac
printf '%s\n' "$*" >> /etc/rc.conf
EOF
cat > "$root/usr/sbin/service" <<'EOF'
#!/bin/sh
set -eu
printf 'service %s\n' "$*" >> /fixture/events
if [ -e /fixture/service-fail ] && [ "$(cat /fixture/service-fail)" = "$*" ]; then exit 9; fi
case "$2" in
    onestatus) [ -e /fixture/running ] ;;
    configtest|reload|start) exit 0 ;;
    *) exit 99 ;;
esac
EOF
cat > "$root/usr/bin/getent" <<'EOF'
#!/bin/sh
[ "$1" = hosts ] || exit 99
[ ! -e /fixture/unresolved ] || exit 2
printf '192.0.2.1 %s\n' "$2"
EOF
mv "$root/usr/bin/fsync" "$root/usr/bin/fsync.real"
cat > "$root/usr/bin/fsync" <<'EOF'
#!/bin/sh
[ ! -e /fixture/sync-fail ] || exit 8
exec /usr/bin/fsync.real "$@"
EOF
chmod 0555 "$root/usr/sbin/sysrc" "$root/usr/sbin/service" "$root/usr/bin/getent" "$root/usr/bin/fsync"
mkdir -p "$workspace/template/etc/syslog.d" "$workspace/template/etc/ssh" "$workspace/template/root/.ssh"
printf 'include /etc/syslog.d\n!admin\n*.info /var/log/admin\n' > "$workspace/template/etc/syslog.conf"
printf '# administrator configuration\n' > "$workspace/template/etc/rc.conf"
printf '# administrator policy\nPasswordAuthentication no\n' > "$workspace/template/etc/ssh/sshd_config"
printf 'Host *\n    StrictHostKeyChecking yes\n' > "$workspace/template/etc/ssh/ssh_config"
printf 'retained host key fixture\n' > "$workspace/template/etc/ssh/ssh_host_ed25519_key"
printf 'retained administrator key fixture\n' > "$workspace/template/root/.ssh/authorized_keys"
chmod 0700 "$workspace/template/root" "$workspace/template/root/.ssh"
chmod 0600 "$workspace/template/etc/ssh/ssh_host_ed25519_key" "$workspace/template/root/.ssh/authorized_keys"
marker='# Written by the xCAT FreeBSD syslog postscript.'

invoke()
{
    label=$1
    shift
    status=0
    env -i PATH="$PATH" MASTER="$master" SYSLOG="$policy" ENABLESSHBETWEENNODES="$ssh_between" \
        chroot "$root" "/scripts/$script" "$@" > "$case_dir/$label.stdout" 2> "$case_dir/$label.stderr" || status=$?
    printf '%s\n' "$status" > "$case_dir/$label.status"
}

snapshot()
{
    mtree -c -k type,uid,gid,mode,nlink,link -K sha256digest -p "$1" | sed '/^#/d'
}

cases=0
for name in log-reload log-start log-repeat log-change log-ignore log-policy log-empty \
    log-bad-ip log-bad-host log-newline log-unresolved log-flags log-N log-sN log-Ns \
    log-double-s log-two-s log-config log-alt-config log-operands log-unknown \
    log-missing-include log-duplicate-include log-dir-link log-dir-mode log-foreign \
    log-file-link log-file-hardlink log-file-mode log-sync-fail log-enable-fail \
    log-reload-fail log-start-fail log-args ssh-reload ssh-start ssh-config-fail \
    ssh-enable-fail ssh-reload-fail ssh-start-fail ssh-share ssh-invalid-policy ssh-args; do
    [ "$selection" = all ] || [ "$selection" = "$name" ] || continue
    cases=$((cases+1))
    case_dir=$workspace/$name
    mkdir "$case_dir"
    rm -rf "$root/etc" "$root/root" "$root/fixture"
    cp -Rp "$workspace/template/etc" "$root/etc"
    cp -Rp "$workspace/template/root" "$root/root"
    mkdir "$root/fixture"
    : > "$root/fixture/events"
    : > "$root/fixture/running"
    printf '%s\n' -s > "$root/fixture/flags"
    script=syslog
    master=192.0.2.1
    policy=
    ssh_between=NO
    expected=0
    unchanged=no
    expected_events=$case_dir/expected-events
    printf 'sysrc syslogd_enable=YES\nservice syslogd onestatus\nservice syslogd reload\n' > "$expected_events"
    case "$name" in
    log-ignore) policy=ignore; master=; unchanged=yes; : > "$expected_events" ;;
    log-policy) policy=other; expected=1 ;;
    log-empty) master=; expected=1 ;;
    log-bad-ip) master=999.0.2.1; expected=1 ;;
    log-bad-host) master='-bad.example'; expected=1 ;;
    log-newline) master='log.example
*.* @evil.example'; expected=1 ;;
    log-unresolved) : > "$root/fixture/unresolved"; expected=1 ;;
    log-flags) printf '%s\n' '-4sv -m 10' > "$root/fixture/flags" ;;
    log-N) printf '%s\n' -N > "$root/fixture/flags" ;;
    log-sN) printf '%s\n' -sN > "$root/fixture/flags" ;;
    log-Ns) printf '%s\n' -Ns > "$root/fixture/flags"; expected=1 ;;
    log-double-s) printf '%s\n' -ss > "$root/fixture/flags"; expected=1 ;;
    log-two-s) printf '%s\n' '-s -s' > "$root/fixture/flags"; expected=1 ;;
    log-config) printf '%s\n' '-s -f /etc/syslog.conf' > "$root/fixture/flags" ;;
    log-alt-config) printf '%s\n' '-s -f /etc/alternate' > "$root/fixture/flags"; expected=1 ;;
    log-operands) printf '%s\n' '-s extra' > "$root/fixture/flags"; expected=1 ;;
    log-unknown) printf '%s\n' -q > "$root/fixture/flags"; expected=1 ;;
    log-missing-include) printf '*.info /var/log/admin\n' > "$root/etc/syslog.conf"; expected=1 ;;
    log-duplicate-include) printf 'include /etc/syslog.d\n' >> "$root/etc/syslog.conf"; expected=1 ;;
    log-dir-link) mv "$root/etc/syslog.d" "$root/etc/alternate"; ln -s alternate "$root/etc/syslog.d"; expected=1 ;;
    log-dir-mode) chmod 0777 "$root/etc/syslog.d"; expected=1 ;;
    log-foreign) printf '# administrator\n*.info /var/log/private\n' > "$root/etc/syslog.d/90-xcat.conf"; expected=1 ;;
    log-file-link) ln -s ../rc.conf "$root/etc/syslog.d/90-xcat.conf"; expected=1 ;;
    log-file-hardlink|log-file-mode)
        printf '%s\n*.info /var/log/old\n' "$marker" > "$root/etc/syslog.d/90-xcat.conf"
        if [ "$name" = log-file-hardlink ]; then
            ln "$root/etc/syslog.d/90-xcat.conf" "$root/etc/other.conf"
        else chmod 0666 "$root/etc/syslog.d/90-xcat.conf"; fi
        expected=1 ;;
    log-sync-fail) : > "$root/fixture/sync-fail"; expected=1 ;;
    log-args) expected=1 ;;
    ssh-*)
        script=remoteshell
        printf 'service sshd configtest\nsysrc sshd_enable=YES\nservice sshd onestatus\nservice sshd reload\n' > "$expected_events"
        case "$name" in
        ssh-config-fail) printf 'sshd configtest\n' > "$root/fixture/service-fail"; expected=1; unchanged=yes
            printf 'service sshd configtest\n' > "$expected_events" ;;
        ssh-share) ssh_between=YES; expected=1; unchanged=yes; : > "$expected_events" ;;
        ssh-invalid-policy) ssh_between=maybe; expected=1; unchanged=yes; : > "$expected_events" ;;
        ssh-args) expected=1; unchanged=yes; : > "$expected_events" ;;
        esac ;;
    esac
    if [ "$script" = syslog ] && [ "$expected" -ne 0 ]; then unchanged=yes; : > "$expected_events"; fi
    case "$name" in
    *-start|*-start-fail)
        rm "$root/fixture/running"
        sed 's/ reload$/ start/' "$expected_events" > "$case_dir/start-events"
        mv "$case_dir/start-events" "$expected_events" ;;
    esac
    case "$name" in
    *-enable-fail)
        : > "$root/fixture/enable-fail"; expected=1
        if [ "$script" = syslog ]; then printf 'sysrc syslogd_enable=YES\n' > "$expected_events"
        else printf 'service sshd configtest\nsysrc sshd_enable=YES\n' > "$expected_events"; unchanged=yes; fi ;;
    *-reload-fail)
        if [ "$script" = syslog ]; then printf 'syslogd reload\n' > "$root/fixture/service-fail"
        else printf 'sshd reload\n' > "$root/fixture/service-fail"; fi; expected=1 ;;
    *-start-fail)
        if [ "$script" = syslog ]; then printf 'syslogd start\n' > "$root/fixture/service-fail"
        else printf 'sshd start\n' > "$root/fixture/service-fail"; fi; expected=1 ;;
    esac
    snapshot "$root/etc" > "$case_dir/etc-before"
    snapshot "$root/root" > "$case_dir/root-before"
    case "$name" in *-args) invoke run extra ;; *) invoke run ;; esac
    [ "$status" -eq "$expected" ]
    cmp "$expected_events" "$root/fixture/events"
    cp -p "$root/fixture/events" "$case_dir/events"
    snapshot "$root/etc" > "$case_dir/etc-after"
    snapshot "$root/root" > "$case_dir/root-after"
    cmp "$case_dir/root-before" "$case_dir/root-after"
    cmp "$workspace/template/etc/ssh/sshd_config" "$root/etc/ssh/sshd_config"
    cmp "$workspace/template/etc/ssh/ssh_config" "$root/etc/ssh/ssh_config"
    cmp "$workspace/template/etc/ssh/ssh_host_ed25519_key" "$root/etc/ssh/ssh_host_ed25519_key"
    if [ "$unchanged" = yes ]; then
        cmp "$case_dir/etc-before" "$case_dir/etc-after"
    elif [ "$script" = syslog ]; then
        printf '%s\n!*\n+*\n:*\n*.*\t@%s\n' "$marker" "$master" > "$case_dir/expected-config"
        cmp "$case_dir/expected-config" "$root/etc/syslog.d/90-xcat.conf"
        [ "$(stat -f '%u:%g:%Lp:%l' "$root/etc/syslog.d/90-xcat.conf")" = 0:0:644:1 ]
        cp -p "$root/etc/syslog.d/90-xcat.conf" "$case_dir/config"
        cmp "$workspace/template/etc/syslog.conf" "$root/etc/syslog.conf"
    fi
    [ "$(find "$root/etc/syslog.d" -name '.xcat.*' | wc -l | tr -d ' ')" -eq 0 ]
    case "$name" in
    log-repeat|log-change)
        inode=$(stat -f %i "$root/etc/syslog.d/90-xcat.conf")
        if [ "$name" = log-change ]; then master=log.example; fi
        : > "$root/fixture/events"
        invoke retry
        [ "$status" -eq 0 ]
        cmp "$expected_events" "$root/fixture/events"
        printf '%s\n!*\n+*\n:*\n*.*\t@%s\n' "$marker" "$master" > "$case_dir/expected-retry"
        cmp "$case_dir/expected-retry" "$root/etc/syslog.d/90-xcat.conf"
        if [ "$name" = log-repeat ]; then [ "$inode" = "$(stat -f %i "$root/etc/syslog.d/90-xcat.conf")" ]; fi
        ;;
    esac
    printf 'PASS %s\n' "$name" | tee -a "$workspace/results"
done
[ "$cases" -gt 0 ]
printf 'PASS cases=%s\n' "$cases"
