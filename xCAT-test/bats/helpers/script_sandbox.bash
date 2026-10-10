#!/usr/bin/env bash

load 'helpers/shell_source'

setup_script_sandbox()
{
    [ "$(uname -s)" = Linux ] || skip 'Script filesystem isolation requires Linux'
    local bwrap utility executable directory
    bwrap=$(PATH=/usr/bin:/bin type -P bwrap) || {
        echo 'Install bubblewrap to run the script tests' >&2
        return 1
    }
    fixture="${BATS_TEST_TMPDIR:?bats-core 1.4 or newer is required}/fixture"
    mkdir -p "$fixture"/{bin,etc,tmp,var,run}
    sandbox=(env -i PATH=/usr/bin:/bin LC_ALL=C "$bwrap"
        --unshare-all --die-with-parent --new-session
        --ro-bind / / --proc /proc --dev /dev
        --bind "$fixture/etc" /etc --bind "$fixture/tmp" /tmp
        --bind "$fixture/var" /var --bind "$fixture/run" /run
        --bind "$fixture" /run/fixture --chdir /tmp
        --setenv PATH /usr/bin:/bin --setenv LC_ALL C)
    for directory in /usr/bin /usr/sbin /bin /sbin; do
        if [ -d "$directory" ] && [ ! -L "$directory" ]; then
            sandbox+=(--ro-bind "$fixture/bin" "$directory")
        fi
    done
    for utility in bash sh timeout "$@"; do
        executable=$(PATH=/usr/bin:/bin type -P "$utility") || {
            echo "Required utility is unavailable: $utility" >&2
            return 1
        }
        cp -L "$executable" "$fixture/bin/$utility"
    done
    if PATH=/usr/bin:/bin type -P coreutils >/dev/null; then
        cp -L "$(PATH=/usr/bin:/bin type -P coreutils)" "$fixture/bin/coreutils"
    fi
    run "${sandbox[@]}" /bin/sh -c 'test ! -e /etc/os-release'
    if [ "$status" -ne 0 ]; then
        echo "Cannot isolate script: $output" >&2
        return 1
    fi
}
