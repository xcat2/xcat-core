#!/usr/bin/env bats

load 'helpers/genesis_sandbox'

@test "script sandbox defaults to a private working directory" {
    setup_script_sandbox pwd
    run "${sandbox[@]}" /bin/pwd
    [ "$status" -eq 0 ]
    [ "$output" = /tmp ]
}

@test "script sandbox lets adapters choose the working directory" {
    setup_script_sandbox --no-chdir pwd
    run "${sandbox[@]}" --chdir /run/fixture /bin/pwd
    [ "$status" -eq 0 ]
    [ "$output" = /run/fixture ]
}

@test "script sandbox exposes only staged tools and private writable directories" {
    setup_script_sandbox cat
    printf 'private\n' >"$fixture/etc/marker"
    run "${sandbox[@]}" /bin/sh -c '
        test ! -e /etc/os-release && test ! -x /usr/bin/id &&
        test -x /bin/sh && test -x /usr/bin/cat &&
        cat /etc/marker &&
        printf tmp > /tmp/marker && printf var > /var/marker &&
        printf run > /run/marker
    '
    [ "$status" -eq 0 ]
    [ "$output" = private ]
    [ "$(cat "$fixture/tmp/marker")" = tmp ]
    [ "$(cat "$fixture/var/marker")" = var ]
    [ "$(cat "$fixture/run/marker")" = run ]
}

@test "tool staging rejects an unavailable command" {
    setup_script_sandbox
    run stage_sandbox_tools xcat_fixture_missing_command
    [ "$status" -ne 0 ]
    [[ "$output" = *'Required utility is unavailable: xcat_fixture_missing_command'* ]]
}

@test "Genesis retains host tools and synthetic kernel inputs" {
    setup_genesis_sandbox doxcat
    printf 'fixture command line\n' >"$fixture/cmdline"
    run "${sandbox[@]}" /bin/sh -c '
        test -x /usr/bin/id && test -r /run/script &&
        test -d /sys/class/net/lo && test ! -e /sys/kernel &&
        test ! -e /etc/os-release && cat /proc/cmdline
    '
    [ "$status" -eq 0 ]
    [ "$output" = 'fixture command line' ]
}
