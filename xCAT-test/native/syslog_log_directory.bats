#!/usr/bin/env bats

load '../bats/helpers/script_sandbox'

setup()
{
    [ "$(id -u)" -eq 0 ] || skip 'native syslog ownership checks require root'
    setup_script_sandbox cat cp dirname grep egrep sed tr uname awk cut head touch mkdir \
        chown chmod stat id sleep logger rm date mktemp
    local index daemon
    # Keep real account IDs so rsyslog can drop its privileges.
    for index in "${!sandbox[@]}"; do
        if [ "${sandbox[$index]}" = --unshare-all ]; then
            sandbox[$index]=--unshare-pid
        fi
    done
    sandbox+=(--unshare-net --unshare-ipc --unshare-uts
        --ro-bind "$(repo_path xCAT/postscripts)" /tmp/postscripts
        --ro-bind "$(repo_path xCAT/xcat-upgrade-functions.sh)" /tmp/upgrade.sh)
    daemon=$(PATH=/usr/sbin:/sbin:/usr/bin:/bin type -P rsyslogd) || return 1
    cp -L "$daemon" "$fixture/bin/rsyslogd-real"
    daemon=$(PATH=/usr/sbin:/sbin:/usr/bin:/bin type -P ip) || return 1
    cp -L "$daemon" "$fixture/bin/ip"
    cp /etc/passwd /etc/group /etc/nsswitch.conf "$fixture/etc/"
    id syslog >/dev/null || return 1
    mkdir -p "$fixture/etc/rsyslog.d" "$fixture/etc/default" \
        "$fixture/etc/systemd/system" "$fixture/var/log" "$fixture/var/lib/rsyslog"
    touch "$fixture/etc/systemd/system/rsyslog.service"
    cat >"$fixture/etc/rsyslog.conf" <<'CONF'
$PrivDropToUser syslog
$PrivDropToGroup syslog
module(load="imudp")
input(type="imudp" address="127.0.0.1" port="1514")
local4.* /var/log/xcat/cluster.log
$IncludeConfig /etc/rsyslog.d/*.conf
CONF
    cat >"$fixture/bin/rsyslogd" <<'SH'
#!/bin/sh
if [ "$1" = -v ] && [ "$SYSLOG_TEST_VERSION" != 8 ]; then
    echo "rsyslogd $SYSLOG_TEST_VERSION.0"
else
    exec /bin/rsyslogd-real "$@"
fi
SH
    cat >"$fixture/bin/systemctl" <<'SH'
#!/bin/bash
set -eu
[ "$*" = 'restart rsyslog' ]
if [ -s /run/rsyslog.pid ]; then
    previous=$(cat /run/rsyslog.pid)
    kill "$previous"
    for ((i=0; i<100; i++)); do
        [ -d "/proc/$previous" ] || break
        sleep .02
    done
    [ ! -d "/proc/$previous" ]
    rm -f /run/rsyslog.pid
fi
/bin/rsyslogd-real -n -i /run/rsyslog.pid -f /etc/rsyslog.conf >>/run/daemon.log 2>&1 </dev/null &
for ((i=0; i<100; i++)); do
    [ ! -s /run/rsyslog.pid ] || exit 0
    sleep .02
done
exit 1
SH
    cat >"$fixture/bin/check-delivery" <<'SH'
#!/bin/bash
set -eu
uid=$(id -u syslog)
expected="^Uid:[[:space:]]+$uid[[:space:]]+$uid[[:space:]]+$uid[[:space:]]+$uid$"
for ((i=0; i<100; i++)); do
    if grep -Eq "$expected" /proc/$(cat /run/rsyslog.pid)/status; then break; fi
    sleep .02
done
grep -Eq "$expected" /proc/$(cat /run/rsyslog.pid)/status
logger -n 127.0.0.1 -P 1514 -d -p local4.info "$1"
for ((i=0; i<100; i++)); do
    if grep -q "$1" /var/log/xcat/cluster.log; then break; fi
    sleep .02
done
grep -q "$1" /var/log/xcat/cluster.log
SH
    cat >"$fixture/bin/log-test" <<'SH'
#!/bin/bash
set -eu
ip link set lo up
rm -f /run/rsyslog.pid
if [ "$SYSLOG_TEST_ROLE" = mn ]; then touch /etc/xCATMN; fi
if [ "$SYSLOG_TEST_VERSION" = 3 ]; then
    echo 'SYSLOGD_OPTIONS="-c 3"' >/etc/default/rsyslog
fi
case "$SYSLOG_TEST_DIRECTORY" in
    absent) ;;
    blocked) touch /var/log/xcat ;;
    *)
        mkdir -m "$SYSLOG_TEST_DIRECTORY" /var/log/xcat
        echo preserved >/var/log/xcat/old.log
        chmod 0600 /var/log/xcat/old.log
        ;;
esac
exec /bin/bash -eu -c "$1"
SH
    chmod +x "$fixture/bin/rsyslogd" "$fixture/bin/systemctl" \
        "$fixture/bin/log-test" "$fixture/bin/check-delivery"
}

run_syslog()
{
    local role=$1 directory=$2 version=$3 osver=$4 code=$5
    run "${sandbox[@]}" --setenv OSVER "$osver" --setenv SYSLOG '' \
        --setenv NTYPE service --setenv SVLOGLOCAL "$([ "$role" = forward ] && echo 0 || echo 1)" \
        --setenv MASTER 127.0.0.1:1515 --setenv SYSLOG_TEST_ROLE "$role" \
        --setenv SYSLOG_TEST_DIRECTORY "$directory" --setenv SYSLOG_TEST_VERSION "$version" \
        /bin/bash /bin/log-test "$code"
    if [ "$status" -ne 0 ]; then
        cat "$fixture/run/daemon.log" >&2
        return 1
    fi
}

@test 'syslog creates a local log directory and delivers as syslog on MN and SN' {
    local role osver
    for role in mn sn; do
        for osver in ubuntu24.04 debian12; do
            run_syslog "$role" absent 8 "$osver" '
                for pass in 1 2; do
                    /tmp/postscripts/syslog
                    test "$(stat -c %U:%G:%a /var/log/xcat)" = syslog:adm:750
                    check-delivery "directory-test-$pass"
                done
            '
            rm -rf "$fixture/var/log/xcat"
            rm -f "$fixture/etc/xCATMN"
        done
    done
}

@test 'syslog preserves existing directory modes and log file ownership' {
    local mode
    for mode in 0700 0750; do
        run_syslog mn "$mode" 8 ubuntu24.04 '
            before=$(stat -c %u:%g:%a /var/log/xcat/old.log)
            /tmp/postscripts/syslog
            test "$(stat -c %a /var/log/xcat)" = "${SYSLOG_TEST_DIRECTORY#0}"
            test "$(stat -c %U:%G /var/log/xcat)" = syslog:adm
            test "$(stat -c %u:%g:%a /var/log/xcat/old.log)" = "$before"
            test "$(cat /var/log/xcat/old.log)" = preserved
            check-delivery restricted-directory-test
        '
        rm -rf "$fixture/var/log/xcat"
    done
}

@test 'syslog prepares the log directory after the real upgrade wrapper' {
    run_syslog mn absent 8 ubuntu24.04 '
        . /tmp/upgrade.sh
        xcat_run_upgrade /tmp/postscripts/syslog
        test "$(stat -c %U:%G /var/log/xcat)" = syslog:adm
        test -s /var/log/xcat/upgrade.log
        check-delivery upgrade-directory-test
    '
}

@test 'syslog retains rsyslog compatibility-mode directory ownership' {
    run_syslog mn absent 3 ubuntu24.04 '
        /tmp/postscripts/syslog
        test "$(stat -c %U:%G:%a /var/log/xcat)" = syslog:adm:750
        check-delivery compatibility-directory-test
    '
}

@test 'syslog retains the legacy reference-directory ownership' {
    run_syslog mn absent 5 ubuntu24.04 '
        chown root:syslog /var/log
        chmod 0775 /var/log
        /tmp/postscripts/syslog
        test "$(stat -c %u:%g /var/log/xcat)" = "$(stat -c %u:%g /var/log)"
        test "$(stat -c %a /var/log/xcat)" = 775
        check-delivery legacy-directory-test
    '
}

@test 'syslog does not create a local directory on forwarding nodes' {
    run_syslog forward absent 8 ubuntu24.04 '
        /tmp/postscripts/syslog
        test ! -e /var/log/xcat
        grep -qx "\*\.\* @127.0.0.1:1515" /etc/rsyslog.d/remote.conf
    '
}

@test 'syslog reports failure when the directory path is a file' {
    run_syslog mn blocked 8 ubuntu24.04 '
        if /tmp/postscripts/syslog; then exit 1; fi
        test -f /var/log/xcat
        test ! -e /run/rsyslog.pid
    '
}
