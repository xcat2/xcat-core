#!/usr/bin/env bash

load 'helpers/shell_source'

setup_genesis_sandbox()
{
    [ "$(uname -s)" = Linux ] || skip 'Genesis filesystem isolation requires Linux'
    local bwrap utility source
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the Genesis script tests' >&2
        return 1
    }
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
    fixture="${BATS_TEST_TMPDIR:?bats-core 1.4 or newer is required}/fixture"
    mkdir -p "$fixture"/{bin,etc/xcat,sys/class/net/lo,tmp,var/lib/dhclient}
    : >"$fixture/cmdline"
    sandbox=(env -i PATH=/usr/bin:/bin LC_ALL=C "$bwrap"
        --unshare-all --die-with-parent --new-session
        --ro-bind / / --tmpfs /run --proc /proc --dev /dev
        --bind "$fixture" /run/fixture --bind "$fixture/tmp" /tmp
        --bind "$fixture/etc" /etc --ro-bind "$fixture/sys" /sys
        --bind "$fixture/var" /var
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
    run "${sandbox[@]}" "$@" timeout 20 /bin/bash /run/script </dev/null
    if [ "$status" -ne "$expected_status" ] && [ "$status" -ne "$alternate_status" ]; then
        printf 'Expected exit %s or %s, got %s\n%s\n' \
            "$expected_status" "$alternate_status" "$status" "$output" >&2
        return 1
    fi
}
