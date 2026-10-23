#!/usr/bin/env bats
#
# pre.rhels10 runs in the EL10 installer. It embeds the install monitor xCAT
# asks for node status, and it reads the install server out of the kernel
# command line. Both were IPv4 only: the monitor opened an AF_INET socket, and
# the server was cut out of the URL at the first colon, which splits an IPv6
# literal.
#
# The monitor tests render the embedded program the way xCAT renders it, run
# it, and speak its protocol. Everything is on the loopback addresses of this
# host; nothing reaches the lab.

load 'helpers/shell_source'

# The port the embedded install monitor listens on. It is fixed in the script.
MONITOR_PORT=3054

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-server/share/xcat/install/scripts/pre.rhels10')"
    command -v socat >/dev/null || skip 'socat is required'
    command -v ss >/dev/null || skip 'ss is required'
    MONITOR="${BATS_TEST_TMPDIR}/install-monitor.py"
    XCATD_PORT=$(( 20000 + RANDOM % 20000 ))
    XCATD_PID=
    MONITOR_PID=
}

teardown()
{
    [ -n "$MONITOR_PID" ] && kill "$MONITOR_PID" 2>/dev/null
    [ -n "$XCATD_PID" ] && kill "$XCATD_PID" 2>/dev/null
    return 0
}

# wait_for_port <port> -- the listener is read from ss rather than by
# connecting, because a probe connection is a peer the monitor would answer.
wait_for_port()
{
    local i
    for i in $(seq 1 100); do
        ss -Hltn "sport = :$1" 2>/dev/null | grep -q . && return 0
        sleep 0.1
    done
    return 1
}

# start_monitor <master> -- render the install monitor pre.rhels10 embeds,
# fill its two substitution tokens the way xCAT fills them, serve the one
# handshake it makes to xcatd, then start it.
start_monitor()
{
    local master="$1" family listen handler
    command -v python3 >/dev/null || skip 'python3 is required'

    awk "/^cat >\\/tmp\\/foo.py <<'EOF'\$/ { copy = 1; next }
         copy && /^EOF\$/ { exit }
         copy { print }" "$SCRIPT" \
      | sed -e "s|#ENV:MASTER_IP#|${master}|g" \
            -e "s|#TABLE:site:key=xcatiport:value#|${XCATD_PORT}|g" >"$MONITOR"
    [ -s "$MONITOR" ] || return 1
    ! grep -q '#ENV:\|#TABLE:' "$MONITOR" || return 1

    case "$master" in
    *:*) family='TCP6'; listen="bind=${master}" ;;
    *)   family='TCP4'; listen="bind=${master}" ;;
    esac

    # The handshake is two lines: xcatd sends "ready", the monitor sends the
    # name it registers under, xcatd answers anything.
    handler="${BATS_TEST_TMPDIR}/xcatd.sh"
    cat >"$handler" <<'HANDLER'
#!/bin/bash
printf 'ready\n'
IFS= read -r registered
printf '%s\n' "$registered" >"$REGISTERED"
printf 'ok\n'
HANDLER
    chmod 0755 "$handler"
    REGISTERED="${BATS_TEST_TMPDIR}/registered"
    : >"$REGISTERED"
    # Detach the stdio of both children: one holding the test's pipes open
    # makes a failure hang instead of go red.
    REGISTERED="$REGISTERED" setsid socat \
        "${family}-LISTEN:${XCATD_PORT},${listen},reuseaddr" "EXEC:$handler" \
        </dev/null >/dev/null 2>&1 &
    XCATD_PID=$!
    wait_for_port "$XCATD_PORT" || return 1

    setsid python3 "$MONITOR" </dev/null >/dev/null 2>&1 &
    MONITOR_PID=$!
    wait_for_port "$MONITOR_PORT"
}

# ask <socat-address> <command> -- send one monitor command, print the answer.
ask()
{
    printf '%s\n' "$2" | socat -T3 - "$1" 2>/dev/null
}

@test "an IPv6 master address makes the install monitor listen on IPv6" {
    start_monitor '::1'
    run ask "TCP6:[::1]:${MONITOR_PORT}" 'stat'
    [ "$status" -eq 0 ]
    [ "$output" = 'installing prep' ]
}

@test "an IPv6 master address makes the install monitor refuse IPv4" {
    start_monitor '::1'
    run ask "TCP4:127.0.0.1:${MONITOR_PORT}" 'stat'
    [ "$output" != 'installing prep' ]
}

@test "an IPv4 master address makes the install monitor listen on IPv4" {
    start_monitor '127.0.0.2'
    run ask "TCP4:127.0.0.2:${MONITOR_PORT},bind=127.0.0.2" 'stat'
    [ "$status" -eq 0 ]
    [ "$output" = 'installing prep' ]
}

@test "the install monitor answers only a peer address the master resolves to" {
    start_monitor '127.0.0.2'
    run ask "TCP4:127.0.0.2:${MONITOR_PORT},bind=127.0.0.1" 'stat'
    [ "$output" != 'installing prep' ]
}

@test "the install monitor registers itself with xcatd over IPv6" {
    start_monitor '::1'
    run cat "${BATS_TEST_TMPDIR}/registered"
    [ "$output" = 'installmonitor' ]
}

@test "a command is recognised with leading whitespace around it" {
    start_monitor '::1'
    run ask "TCP6:[::1]:${MONITOR_PORT}" '  stat  '
    [ "$status" -eq 0 ]
    [ "$output" = 'installing prep' ]
}

@test "a screendump console that is not a number is refused" {
    start_monitor '::1'
    run ask "TCP6:[::1]:${MONITOR_PORT}" 'screendump x'
    [ "$output" = 'invalid virtual console' ]
}

@test "a screendump argument carrying a shell command is refused and not run" {
    start_monitor '::1'
    local marker="${BATS_TEST_TMPDIR}/ran-a-shell-command"
    run ask "TCP6:[::1]:${MONITOR_PORT}" "screendump 1;touch ${marker}"
    [ "$output" = 'invalid virtual console' ]
    [ ! -e "$marker" ]
}

@test "a numeric screendump console reads that virtual console and no other" {
    start_monitor '::1'
    run ask "TCP6:[::1]:${MONITOR_PORT}" 'screendump 7'
    [ "$output" != 'invalid virtual console' ]
    [[ "$output" == *'/dev/vcs7'* ]] || [ -r /dev/vcs7 ]
}

# extract_url_host and the expression that feeds it. The install server is
# read out of /proc/cmdline, where an EL10 IPv6 install writes a bracketed
# authority.
url_host()
{
    local lib="${BATS_TEST_TMPDIR}/url.sh"
    extract_shell_function "$SCRIPT" 'extract_url_host' >"$lib" || return 1
    # shellcheck disable=SC1090
    . "$lib"
    extract_url_host "$1"
}

@test "an IPv4 install URL yields its address" {
    run url_host 'http://192.0.2.1/install/rhels10/x86_64'
    [ "$status" -eq 0 ]
    [ "$output" = '192.0.2.1' ]
}

@test "an IPv4 install URL with a port yields the address without the port" {
    run url_host 'http://192.0.2.1:8080/install/rhels10/x86_64'
    [ "$output" = '192.0.2.1' ]
}

@test "a bracketed IPv6 install URL yields the address without the brackets" {
    run url_host 'http://[2001:db8::1]/install/rhels10/x86_64'
    [ "$output" = '2001:db8::1' ]
}

@test "a bracketed IPv6 install URL with a port yields only the address" {
    run url_host 'http://[2001:db8::1]:8080/install/rhels10/x86_64'
    [ "$output" = '2001:db8::1' ]
}

@test "a hostname install URL yields the hostname" {
    run url_host 'https://mn01.cluster.example/install/rhels10/x86_64'
    [ "$output" = 'mn01.cluster.example' ]
}

# The expression that finds the install URL in the kernel command line, taken
# from the script rather than retyped, so a change to it is measured here.
cmdline_host()
{
    local expression url
    expression="$(sed -n "s/^NEXTSERVER_URL=\"\$(grep -oE '\(.*\)' \/proc\/cmdline.*\$/\1/p" \
        "$SCRIPT")"
    [ -n "$expression" ] || return 1
    url="$(printf '%s\n' "$1" | grep -oE "$expression" | head -n 1)"
    url_host "$url"
}

@test "the install server is found in an IPv6 EL10 kernel command line" {
    run cmdline_host 'ro inst.repo=http://[2001:db8::1]/install/rhels10/x86_64 inst.ks=http://[2001:db8::1]/install/autoinst/node01'
    [ "$status" -eq 0 ]
    [ "$output" = '2001:db8::1' ]
}

@test "the install server is found in an IPv4 kernel command line" {
    run cmdline_host 'ro inst.repo=http://192.0.2.1:8080/install/rhels10/x86_64'
    [ "$status" -eq 0 ]
    [ "$output" = '192.0.2.1' ]
}
