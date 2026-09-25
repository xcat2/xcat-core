#!/usr/bin/env bats
#
# genesis-action runs in the OpenEmbedded Genesis image. It reads the node action (the destiny)
# from xCAT and runs it: discovery, a wait state, an approved command, a reboot into an
# install, or a poweroff. getdestiny and nextdestiny are scratch scripts that answer from a
# queue file. The other commands are scratch scripts that log their arguments.

load 'helpers/shell_source'

INIT_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files'

setup()
{
    ACTION_SCRIPT="$(require_repo_file "$INIT_FILES/genesis-action")"
    root="$BATS_TEST_TMPDIR"
    bin="$root/bin"
    state_dir="$root/run"
    status_dir="$state_dir/status"
    approved_dir="$root/actions"
    destiny_file="$state_dir/destiny"
    command_log="$root/commands.log"
    mkdir -p "$bin" "$status_dir" "$approved_dir"
    printf '%s\n' XCATDEST=192.0.2.10:3001 XCATMASTER=192.0.2.10 XCATPORT=3001 \
        XCAT_INTERFACE=eth0 XCAT_SOURCE_ADDRESS=192.0.2.98 >"$state_dir/genesis.env"
    printf '42.00 80.00\n' >"$root/uptime"

    cat >"$bin/getdestiny" <<'SH'
#!/bin/sh
printf 'getdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
metadata=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --metadata) metadata=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -s "$XCAT_TEST_GETDESTINY_QUEUE" ] || exit 1
response=$(head -n 1 "$XCAT_TEST_GETDESTINY_QUEUE")
tail -n +2 "$XCAT_TEST_GETDESTINY_QUEUE" >"$XCAT_TEST_GETDESTINY_QUEUE.new"
mv "$XCAT_TEST_GETDESTINY_QUEUE.new" "$XCAT_TEST_GETDESTINY_QUEUE"
if [ -n "$metadata" ]; then
    printf '%s\n' 'XCAT_NODE_NAME=node042' "XCAT_DESTINY=$response" >"$metadata"
fi
printf '%s\n' "$response"
SH
    cat >"$bin/nextdestiny" <<'SH'
#!/bin/sh
printf 'nextdestiny %s\n' "$*" >>"$XCAT_TEST_LOG"
[ -s "$XCAT_TEST_NEXTDESTINY_QUEUE" ] || exit 1
response=$(head -n 1 "$XCAT_TEST_NEXTDESTINY_QUEUE")
tail -n +2 "$XCAT_TEST_NEXTDESTINY_QUEUE" >"$XCAT_TEST_NEXTDESTINY_QUEUE.new"
mv "$XCAT_TEST_NEXTDESTINY_QUEUE.new" "$XCAT_TEST_NEXTDESTINY_QUEUE"
printf '%s\n' "$response"
SH
    printf '#!/bin/sh\nprintf "logger %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/logger"
    printf '#!/bin/sh\nprintf "%%s\\n" discover >>"$XCAT_TEST_LOG"\n' >"$bin/discover"
    printf '#!/bin/sh\nprintf "%%s\\n" getcert >>"$XCAT_TEST_LOG"\n: >"$XCAT_TEST_CERTIFICATE_FILE"\n' >"$bin/getcert"
    printf '#!/bin/sh\nprintf "reboot-control %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/reboot-control"
    printf '#!/bin/sh\nprintf "poweroff-control %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$bin/poweroff-control"
    printf '#!/bin/sh\nprintf "ipmitool %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n[ "${XCAT_TEST_IPMI-0}" = 1 ]\n' >"$bin/ipmitool"
    printf '#!/bin/sh\nprintf inventory >>"$XCAT_TEST_LOG"\nprintf " <%%s>" "$@" >>"$XCAT_TEST_LOG"\nprintf "\\n" >>"$XCAT_TEST_LOG"\n' >"$approved_dir/inventory"
    printf '#!/bin/sh\nprintf "%%s\\n" bmcsetup >>"$XCAT_TEST_LOG"\n' >"$approved_dir/bmcsetup"
    chmod 0755 "$bin"/* "$approved_dir"/*

    export PATH="$bin:$PATH"
    export XCAT_STATE_DIR="$state_dir"
    export XCAT_STATUS_COMMAND="$(require_repo_file "$INIT_FILES/genesis-status")"
    export XCAT_STATUS_DIR="$status_dir"
    export XCAT_DESTINY_FILE="$destiny_file"
    export XCAT_METADATA_FILE="$state_dir/xcat-response.env"
    export XCAT_NETWORK_FILE="$state_dir/genesis.env"
    export XCAT_DISCOVER_COMMAND="$bin/discover"
    export XCAT_CERTIFICATE_COMMAND="$bin/getcert"
    export XCAT_CERTIFICATE_FILE="$root/cert.pem"
    export XCAT_GETDESTINY_COMMAND="$bin/getdestiny"
    export XCAT_NEXTDESTINY_COMMAND="$bin/nextdestiny"
    export XCAT_ACTION_COMMAND_DIR="$approved_dir"
    export XCAT_REBOOT_COMMAND="$bin/reboot-control"
    export XCAT_POWEROFF_COMMAND="$bin/poweroff-control"
    export XCAT_ACTION_POLL_SECONDS=0
    export XCAT_ACTION_REQUEST_TIMEOUT=2
    export XCAT_ACTION_OPERATION_TIMEOUT=2
    export XCAT_UPTIME_FILE="$root/uptime"
    export XCAT_GENESIS_FUNCTIONS="$(require_repo_file "$INIT_FILES/genesis-functions")"
    export XCAT_TEST_LOG="$command_log"
    export XCAT_TEST_GETDESTINY_QUEUE="$root/getdestiny.queue"
    export XCAT_TEST_NEXTDESTINY_QUEUE="$root/nextdestiny.queue"
    export XCAT_TEST_CERTIFICATE_FILE="$root/cert.pem"
}

# Run genesis-action for one destiny. GETDESTINY and NEXTDESTINY set the queued xCAT
# answers, NO_CERTIFICATE starts without a certificate, MAX_STEPS and IPMI pass through.
# Sets $status, $log (the command log) and $record (the published action status).
run_action()
{
    printf '%s\n' "$1" >"$destiny_file"
    printf '%s' "${GETDESTINY-$1
}" >"$XCAT_TEST_GETDESTINY_QUEUE"
    printf '%s' "${NEXTDESTINY-standby
}" >"$XCAT_TEST_NEXTDESTINY_QUEUE"
    rm -f "$command_log" "$XCAT_CERTIFICATE_FILE" "$status_dir/action.env"
    [ -n "${NO_CERTIFICATE-}" ] || printf 'certificate\n' >"$XCAT_CERTIFICATE_FILE"
    status=0
    XCAT_ACTION_MAX_STEPS="${MAX_STEPS:-1}" XCAT_TEST_IPMI="${IPMI:-0}" \
        /bin/bash "$ACTION_SCRIPT" </dev/null >/dev/null 2>&1 || status=$?
    log="$(cat "$command_log" 2>/dev/null || true)"
    record="$(cat "$status_dir/action.env" 2>/dev/null || true)"
}

has_line()
{
    grep -Eq "$2" <<<"$1"
}

# Not "! has_line": bash ignores errexit for a command inverted with "!".
has_no_line()
{
    ! grep -Eq "$2" <<<"$1"
}

@test "discovery sends inventory, enrolls a certificate, then queries xCAT and loads the node action" {
    GETDESTINY=$'standby\n' run_action discover
    [ "$status" -eq 0 ]
    has_line "$log" '^discover$'
    has_line "$log" '^getcert$'
    [ "$(grep -nx discover <<<"$log" | cut -d: -f1)" -lt "$(grep -n '^getdestiny ' <<<"$log" | head -n1 | cut -d: -f1)" ]
    [ "$(cat "$destiny_file")" = standby ]
}

@test "shell becomes a managed wait state that accepts a remote action change, and opens no shell" {
    GETDESTINY=$'install test-image\n' run_action shell
    [ "$status" -eq 0 ]
    has_no_line "$log" '(^|/)bash(\s|$)'
    [ "$(cat "$destiny_file")" = 'install test-image' ]
}

@test "standby polls xCAT, obtains a missing certificate, and publishes an idle state" {
    GETDESTINY=$'standby\nstandby\n' NO_CERTIFICATE=1 MAX_STEPS=2 run_action standby
    [ "$status" -eq 0 ]
    has_line "$log" '^getcert$'
    has_line "$record" '^STATE=IDLE$'
    has_line "$record" '^VERIFIED_SECONDS=42$'
}

@test "osimage and ondiscover complete and advance the action chain" {
    for action in osimage ondiscover; do
        run_action "$action"
        [ "$status" -eq 0 ]
        has_line "$log" '^nextdestiny '
    done
}

@test "an approved command completes, gets its arguments unevaluated, and advances the chain" {
    run_action 'runcmd=inventory storage safe;reboot'
    [ "$status" -eq 0 ]
    has_line "$log" '^inventory <storage> <safe;reboot>$'
    has_line "$log" '^nextdestiny '
}

@test "sequential discovery can run BMC setup, which advances the chain" {
    run_action runcmd=bmcsetup
    [ "$status" -eq 0 ]
    has_line "$log" '^bmcsetup$'
    has_line "$log" '^nextdestiny '
}

@test "an unpackaged command is rejected with a specific failure code" {
    run_action runcmd=unpackaged
    [ "$status" -ne 0 ]
    has_line "$record" '^CODE=ACTION_COMMAND_NOT_APPROVED$'
}

@test "runimage, configraid and sysclone fail closed and report their migration status" {
    for pair in runimage:UNSAFE_LEGACY_ACTION configraid:LEGACY_STORAGE_ACTION \
        sysclone:LEGACY_SYSCLONE_ACTION; do
        run_action "${pair%%:*}"
        [ "$status" -ne 0 ]
        has_line "$record" "^CODE=${pair#*:}\$"
    done
}

@test "boot and reboot advance the chain, request a one-time network boot and a reboot" {
    for action in boot reboot; do
        IPMI=1 run_action "$action"
        [ "$status" -eq 0 ]
        has_line "$log" '^nextdestiny '
        has_line "$log" '^ipmitool chassis bootdev pxe$'
        has_line "$log" '^reboot-control reboot$'
    done
}

@test "install, netboot and statelite keep the server-selected chain position and reboot" {
    for action in install netboot statelite; do
        run_action "$action"
        [ "$status" -eq 0 ]
        has_no_line "$log" '^nextdestiny '
        has_line "$log" '^reboot-control reboot$'
    done
}

@test "shutdown requests a poweroff" {
    run_action shutdown
    [ "$status" -eq 0 ]
    has_line "$log" '^poweroff-control poweroff$'
}

@test "an xCAT error action fails and stays visible" {
    run_action 'error=policy denied'
    [ "$status" -ne 0 ]
    has_line "$record" '^CODE=XCAT_ACTION_ERROR$'
}

@test "an unknown action fails with a specific failure code" {
    run_action unknown
    [ "$status" -ne 0 ]
    has_line "$record" '^CODE=XCAT_ACTION_UNSUPPORTED$'
}

@test "a failed refresh uses the previously received action, and the failed poll stays visible" {
    GETDESTINY='' run_action standby
    [ "$status" -eq 0 ]
    has_line "$record" '^STATE=DEGRADED$'
}
