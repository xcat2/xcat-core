#!/usr/bin/env bash

load 'helpers/script_sandbox'

setup_genesis_sandbox()
{
    setup_filesystem_sandbox || return
    local utility source
    for utility in bash cat cp awk grep sed sort tr tail rm wc cut head uname timeout; do
        PATH=/usr/bin:/bin type -P "$utility" >/dev/null || {
            echo "Required utility is unavailable: $utility" >&2
            return 1
        }
    done
    source=$(repo_path "xCAT-genesis-scripts/usr/bin/$1")
    [ -r "$source" ] || {
        echo "Required Genesis script is unreadable: $source" >&2
        return 1
    }
    mkdir -p "$fixture"/{etc/xcat,sys/class/net/lo,var/lib/dhclient} || return
    : >"$fixture/cmdline" || return
    sandbox+=(--tmpfs /run --bind "$fixture" /run/fixture
        --ro-bind "$fixture/sys" /sys
        --ro-bind "$fixture/cmdline" /proc/cmdline
        --ro-bind "$source" /run/script --chdir /tmp
        --setenv PATH /run/fixture/bin:/usr/bin:/bin --setenv LC_ALL C)
    if [ -d /etc/alternatives ]; then
        sandbox+=(--ro-bind /etc/alternatives /etc/alternatives)
    fi
    run "${sandbox[@]}" /bin/bash -c 'command -v awk && test -r /run/script'
    if [ "$status" -ne 0 ]; then
        echo "Cannot isolate Genesis script: $output" >&2
        return 1
    fi
}

run_genesis()
{
    local expected_status=$1 alternate_status
    shift
    # GNU timeout reports a child that a signal killed as 128+signal. The uutils timeout of
    # Ubuntu 26.04 reports the signal number alone, so one SIGTERM is 143 or 15 by platform.
    alternate_status=$expected_status
    if [ "$expected_status" -gt 128 ]; then
        alternate_status=$((expected_status - 128))
    fi
    # A slow host needs over 30 s for one run. GENESIS_SANDBOX_TIMEOUT overrides the cap.
    run "${sandbox[@]}" "$@" timeout "${GENESIS_SANDBOX_TIMEOUT:-120}" /bin/bash /run/script </dev/null
    if [ "$status" -ne "$expected_status" ] && [ "$status" -ne "$alternate_status" ]; then
        printf 'Expected exit %s or %s, got %s\n%s\n' \
            "$expected_status" "$alternate_status" "$status" "$output" >&2
        return 1
    fi
}
