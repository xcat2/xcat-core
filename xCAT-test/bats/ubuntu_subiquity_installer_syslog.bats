#!/usr/bin/env bats
#
# pre.ubuntu.subiquity starts a syslog forwarder inside the Subiquity live installer. The
# forwarder cannot be bounded from its configuration: in the 24.04 installer rsyslogd holds
# 11.9G of a 16G node while its message queue is empty. It runs in the subiquity-server
# cgroup, so the kernel OOM killer stopped the installer, systemd started a second server, and
# that server ran curtin partitioning over a disk the first curtin still held.
#
# So the forwarder must start in a cgroup of its own with a memory limit. Run the routine with
# the launcher replaced, and read the command line it asked for.

bats_require_minimum_version 1.5.0

load 'helpers/shell_source'

setup()
{
    PRE_SCRIPT="$(repo_path 'xCAT-server/share/xcat/install/scripts/pre.ubuntu.subiquity')"
    [ -r "$PRE_SCRIPT" ] || skip "$PRE_SCRIPT is required"
    LAUNCHED="${BATS_TEST_TMPDIR}/launched"
    : >"$LAUNCHED"

    # Sourcing is safe only while the script returns at its guard. Without the guard it would
    # run the install here, and that writes /etc/rsyslog.conf on the host. CI runs as root.
    if ! grep -q 'XCAT_PRE_SOURCE_ONLY' "$PRE_SCRIPT"; then
        echo "$PRE_SCRIPT has no source guard; refusing to run it" >&2
        return 1
    fi

    # bash resolves a function before PATH, so the routine runs as written and nothing starts a
    # daemon. command -v reports a function, so the routine also finds its launcher here.
    systemd-run() { printf 'systemd-run %s\n' "$*" >>"$LAUNCHED"; }
    rsyslogd() { printf 'rsyslogd %s\n' "$*" >>"$LAUNCHED"; }

    XCAT_PRE_SOURCE_ONLY=1 . "$PRE_SCRIPT"
}

@test "the forwarder starts through the launcher that can limit it" {
    run xcat_start_installer_rsyslog /etc/rsyslog.conf
    [ "$status" -eq 0 ]
    grep -q '^systemd-run .*rsyslogd -n -f /etc/rsyslog.conf$' "$LAUNCHED"
}

# 128M is about 0.8% of the node this was measured on. The ceiling keeps a later edit from
# raising the limit to something the installer cannot spare.
@test "the forwarder gets a memory limit the installer can spare" {
    local limit
    run xcat_start_installer_rsyslog /etc/rsyslog.conf
    [ "$status" -eq 0 ]
    limit="$(sed -n 's/.*--property=MemoryMax=\([0-9]*\)M.*/\1/p' "$LAUNCHED")"
    [ -n "$limit" ]
    [ "$limit" -gt 0 ]
    [ "$limit" -le 256 ]
}

@test "the limited forwarder cannot fall back to swap" {
    run xcat_start_installer_rsyslog /etc/rsyslog.conf
    [ "$status" -eq 0 ]
    grep -q -- '--property=MemorySwapMax=0' "$LAUNCHED"
}

@test "the forwarder never starts unlimited when it cannot be limited" {
    local empty="${BATS_TEST_TMPDIR}/nopath"
    mkdir -p "$empty"
    unset -f systemd-run
    PATH="$empty" run xcat_start_installer_rsyslog /etc/rsyslog.conf
    [ "$status" -eq 0 ]
    run -1 grep -q '^rsyslogd ' "$LAUNCHED"
}
