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
    local expected_status=$1
    shift
    run "${sandbox[@]}" "$@" timeout 20 /bin/bash /run/script </dev/null
    if [ "$status" -ne "$expected_status" ]; then
        printf 'Expected exit %s, got %s\n%s\n' "$expected_status" "$status" "$output" >&2
        return 1
    fi
}
