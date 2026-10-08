#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'Postscript filesystem isolation requires Linux'
    command -v bwrap >/dev/null || { echo 'bubblewrap is required' >&2; return 1; }
    fixture="${BATS_TEST_TMPDIR:?bats-core 1.4 or newer is required}/network"
    mkdir -p "$fixture"/{bin,etc/sysconfig/network-scripts,etc/yum.repos.d,var/log/xcat,tmp}
    : >"$fixture/nmcli.log"
    : >"$fixture/logger.log"
    printf '%s\n' 'primary uplink:activated' 'backup:deactivated' 'lo:activated' \
        'storage fabric:activated' ':activated' >"$fixture/connections"
    cat >"$fixture/bin/nmcli" <<'SH'
#!/bin/sh
printf '<%s>' "$@" >>/work/nmcli.log
printf '\n' >>/work/nmcli.log
case "$*" in
    '-g NAME,STATE con show') cat /work/connections ;;
    'con mod '* ) : ;;
    *) exit 97 ;;
esac
SH
    cat >"$fixture/bin/logger" <<'SH'
#!/bin/sh
printf '<%s>' "$@" >>/work/logger.log
printf '\n' >>/work/logger.log
SH
    cat >"$fixture/bin/ethtool" <<'SH'
#!/bin/sh
test "$1" = eth0 || exit 97
printf 'Link detected: %s\n' "$(cat /work/link)"
SH
    chmod +x "$fixture/bin/"*
    printf 'no\n' >"$fixture/link"
    sandbox=(env -i PATH=/usr/bin:/bin bwrap --unshare-all --die-with-parent --new-session
        --tmpfs / --ro-bind /usr /usr --ro-bind /bin /bin
        --ro-bind /lib /lib --proc /proc --dev /dev
        --bind "$fixture" /work --bind "$fixture/etc" /etc
        --bind "$fixture/tmp" /tmp --bind "$fixture/var" /var
        --setenv PATH /work/bin:/usr/bin:/bin --setenv LC_ALL C)
    [ ! -d /etc/alternatives ] || sandbox+=(--ro-bind /etc/alternatives /etc/alternatives)
    [ ! -d /lib64 ] || sandbox+=(--ro-bind /lib64 /lib64)
}

render_and_run()
{
    run env -i PATH=/usr/bin:/bin perl "$(repo_path xCAT-test/bats/fixtures/render-network-post.pl)" \
        "$1" "$fixture" "${2:-1}"
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
    run "${sandbox[@]}" timeout 20 /bin/bash /work/post
    [ "$status" -eq 0 ] || { echo "$output" >&2; return 1; }
}

expect_connections()
{
    printf '%s\n' '<-g><NAME,STATE><con><show>' \
        '<con><mod><primary uplink><connection.autoconnect><yes>' \
        '<con><mod><storage fabric><connection.autoconnect><yes>' >"$fixture/expected"
    cmp "$fixture/expected" "$fixture/nmcli.log"
}

@test "rendered EL8/9 postscript activates only active connections and logs their names" {
    render_and_run 8
    expect_connections
    printf '%s\n' \
        '<-n><192.0.2.10><-t><xcat><-p><local4.info><set connection primary uplink to be activated on system boot>' \
        '<-n><192.0.2.10><-t><xcat><-p><local4.info><set connection storage fabric to be activated on system boot>' >"$fixture/expected"
    cmp "$fixture/expected" "$fixture/logger.log"
    grep -Fq 'set connection primary uplink to be activated' "$fixture/var/log/xcat/xcat.log"
}

@test "rendered EL10 postscript activates connections without logging" {
    render_and_run 10
    expect_connections
    [ ! -s "$fixture/logger.log" ]
    [ ! -e "$fixture/var/log/xcat/xcat.log" ]
}

@test "EL8/9 keeps connection logging disabled when site debugging is off" {
    render_and_run 8 0
    expect_connections
    [ ! -s "$fixture/logger.log" ]
}

@test "EL8/9 activates a linked ifcfg interface without falling back to NetworkManager" {
    printf 'ONBOOT=no\n' >"$fixture/etc/sysconfig/network-scripts/ifcfg-eth0"
    printf 'ONBOOT=no\n' >"$fixture/etc/sysconfig/network-scripts/ifcfg-lo"
    printf 'yes\n' >"$fixture/link"
    render_and_run 8
    [ ! -s "$fixture/nmcli.log" ]
    grep -Fxq ONBOOT=yes "$fixture/etc/sysconfig/network-scripts/ifcfg-eth0"
    grep -Fxq ONBOOT=no "$fixture/etc/sysconfig/network-scripts/ifcfg-lo"
}

@test "EL8/9 falls back to NetworkManager when ifcfg interfaces have no link" {
    printf 'ONBOOT=no\n' >"$fixture/etc/sysconfig/network-scripts/ifcfg-eth0"
    render_and_run 8
    expect_connections
    grep -Fxq ONBOOT=no "$fixture/etc/sysconfig/network-scripts/ifcfg-eth0"
}

@test "both postscripts leave inactive connections alone" {
    printf '%s\n' 'backup:deactivated' 'lo:activated' ':activated' >"$fixture/connections"
    for version in 8 10; do
        : >"$fixture/nmcli.log"
        render_and_run "$version"
        printf '%s\n' '<-g><NAME,STATE><con><show>' >"$fixture/expected"
        cmp "$fixture/expected" "$fixture/nmcli.log"
        [ ! -s "$fixture/logger.log" ]
    done
}

@test "both postscripts disable vendor repositories while preserving custom repositories" {
    for version in 8 10; do
        printf '[vendor]\nenabled = 1\n' >"$fixture/etc/yum.repos.d/rocky.repo"
        printf '[custom]\nenabled=1\n' >"$fixture/etc/yum.repos.d/custom.repo"
        render_and_run "$version"
        grep -Fxq enabled=0 "$fixture/etc/yum.repos.d/rocky.repo"
        grep -Fxq enabled=1 "$fixture/etc/yum.repos.d/custom.repo"
    done
}
