#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    XCATLIB="$(repo_path 'xCAT/postscripts/xcatlib.sh')"
    [ -r "$XCATLIB" ] || skip "$XCATLIB is required"
    export XCATLIB
}

run_restart_fallback()
{
    ps()
    {
        cat <<'EOF'
root      4321  0.0  0.0  15432  2048 ?        Ss   10:00   0:00 /usr/sbin/sshd
EOF
    }
    kill()
    {
        printf '%s\n' "$*" >>"$KILL_LOG"
        [ "$1" = "-0" ] && return 1
        return 0
    }
    sleep() { :; }
    sshd()
    {
        printf '%s\n' start >>"$SSHD_LOG"
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

@test "remoteshell restart fallback sends an uncatchable signal before starting sshd" {
    KILL_LOG="${BATS_TEST_TMPDIR}/kill.log"
    SSHD_LOG="${BATS_TEST_TMPDIR}/sshd.log"
    export KILL_LOG SSHD_LOG

    run run_restart_fallback
    [ "$status" -eq 0 ]
    grep -Fxq -- '-9 4321' "$KILL_LOG"
    ! grep -Eq '^9( |$)' "$KILL_LOG"
    [ "$(read_file_or_empty "$SSHD_LOG")" = "start" ]
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
