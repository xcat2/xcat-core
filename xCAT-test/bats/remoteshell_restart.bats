#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load 'helpers/shell_source'

setup()
{
    XCATLIB="$(repo_path 'xCAT/postscripts/xcatlib.sh')"
    [ -r "$XCATLIB" ] || skip "$XCATLIB is required"
    export XCATLIB
}

run_restart_fallback()
{
    local poll_count=0

    ps()
    {
        cat <<'EOF'
root      4321  0.0  0.0  15432  2048 ?        Ss   10:00   0:00 /usr/sbin/sshd
EOF
    }
    kill()
    {
        if [ "$1" = "-9" ]; then
            printf 'kill %s\n' "$*" >>"$EVENT_LOG"
            return 0
        fi

        poll_count=$((poll_count + 1))
        if [ "$poll_count" -eq 1 ]; then
            printf 'poll %s alive\n' "$2" >>"$EVENT_LOG"
            return 0
        fi
        printf 'poll %s gone\n' "$2" >>"$EVENT_LOG"
        return 1
    }
    sleep() { :; }
    sshd()
    {
        printf '%s\n' start >>"$EVENT_LOG"
    }

    source "$XCATLIB"
    xcat_restart_sshd_after_failed_service_restart sshd
}

run_wait_for_processes()
{
    local rc

    source "$XCATLIB"
    xcat_wait_for_processes_to_exit "$*" 3
    rc=$?
    printf '%s\n' "$rc"
    return 0
}

@test "remoteshell restart fallback kills, waits, then starts sshd" {
    EVENT_LOG="${BATS_TEST_TMPDIR}/events.log"
    export EVENT_LOG

    run run_restart_fallback
    [ "$status" -eq 0 ]
    [ "$(read_file_or_empty "$EVENT_LOG")" = $'kill -9 4321\npoll 4321 alive\npoll 4321 gone\nstart' ]
    run -1 grep -Eq '^kill 9( |$)' "$EVENT_LOG"
}

@test "remoteshell wait loop reports a still-running process and gives up" {
    local child

    sleep 30 &
    child=$!

    run run_wait_for_processes "$child"
    kill -KILL "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true

    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "remoteshell wait loop returns as soon as killed processes are gone" {
    run run_wait_for_processes 999999
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}
