#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    SYSLOG="$(repo_path 'xCAT/postscripts/syslog')"
    [ -r "$SYSLOG" ] || skip "$SYSLOG is required"
    RECEIVER_FUNCTION="${BATS_TEST_TMPDIR}/receiver.bash"
    extract_shell_function "$SYSLOG" config_native_rsyslog_receiver >"$RECEIVER_FUNCTION"
    RECEIVER_CONF="${BATS_TEST_TMPDIR}/rsyslog.conf"
    ALLOCATED_PATH="${BATS_TEST_TMPDIR}/expanded config"
    ALLOCATION_OUTPUT="$ALLOCATED_PATH"
    ALLOCATION_STATUS=0
    VALIDATION_STATUS=0
    RSYSLOG_LOG="${BATS_TEST_TMPDIR}/rsyslog.log"
    REMOVE_LOG="${BATS_TEST_TMPDIR}/remove.log"
    printf '# existing configuration\n' >"$RECEIVER_CONF"
}

run_receiver()
{
    local conf_file="$RECEIVER_CONF"

    mktemp()
    {
        [ "$ALLOCATION_STATUS" -eq 0 ] || return "$ALLOCATION_STATUS"
        if [ -n "$ALLOCATION_OUTPUT" ]; then
            : >"$ALLOCATION_OUTPUT"
            printf '%s\n' "$ALLOCATION_OUTPUT"
        fi
    }
    rsyslogd()
    {
        printf '%s\n' "$@" >"$RSYSLOG_LOG"
        [ "$VALIDATION_STATUS" -eq 0 ] || return "$VALIDATION_STATUS"
        if [ -n "$5" ]; then
            cat "$3" >"$5"
        fi
    }
    rm()
    {
        printf '%s\n' "$@" >"$REMOVE_LOG"
        command rm "$@"
    }

    source "$RECEIVER_FUNCTION"
    config_native_rsyslog_receiver "$RECEIVER_CONF"
}

@test "native syslog receiver removes its expanded configuration after success" {
    run run_receiver

    [ "$status" -eq 0 ]
    [ "$(cat "$REMOVE_LOG")" = "$(printf '%s\n' -f "$ALLOCATED_PATH")" ]
    [ ! -e "$ALLOCATED_PATH" ]
    [ "$(cat "$RECEIVER_CONF")" = $'# existing configuration\nmodule(load="imudp")\ninput(type="imudp" port="514")\nmodule(load="imtcp")\ninput(type="imtcp" port="514")' ]
}

@test "native syslog receiver removes its expanded configuration after validation fails" {
    VALIDATION_STATUS=37

    run run_receiver

    [ "$status" -eq 37 ]
    [ "$(cat "$REMOVE_LOG")" = "$(printf '%s\n' -f "$ALLOCATED_PATH")" ]
    [ ! -e "$ALLOCATED_PATH" ]
    [ "$(cat "$RECEIVER_CONF")" = '# existing configuration' ]
}

@test "native syslog receiver returns an allocation failure before validation or cleanup" {
    ALLOCATION_STATUS=43

    run run_receiver

    [ "$status" -eq 43 ]
    [ ! -e "$RSYSLOG_LOG" ]
    [ ! -e "$REMOVE_LOG" ]
    [ ! -e "$ALLOCATED_PATH" ]
    [ "$(cat "$RECEIVER_CONF")" = '# existing configuration' ]
}

@test "native syslog receiver skips cleanup when allocation succeeds with an empty path" {
    ALLOCATION_OUTPUT=

    run run_receiver

    [ "$status" -eq 0 ]
    [ -s "$RSYSLOG_LOG" ]
    [ ! -e "$REMOVE_LOG" ]
    [ "$(cat "$RECEIVER_CONF")" = '# existing configuration' ]
}
