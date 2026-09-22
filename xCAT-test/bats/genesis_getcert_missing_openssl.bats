#!/usr/bin/env bats
#
# Drive getcert with openssl absent, and with a certificate key that is not ready yet.
# doxcat runs getcert in the foreground and ignores its status, so a wait with no bound stops
# the boot and prints nothing.

load 'helpers/shell_source'

setup()
{
    GETCERT="$(repo_path 'xCAT-genesis-scripts/usr/bin/getcert')"
    [ -r "$GETCERT" ] || skip "$GETCERT is required"
    COUNTER="${BATS_TEST_TMPDIR}/req-count"
    export GETCERT COUNTER
}

write_stub()
{
    local dir="$1" name="$2" body="$3"
    printf '#!/bin/sh\n%s\n' "$body" >"$dir/$name"
    chmod 0755 "$dir/$name"
}

# A PATH directory holding the commands getcert runs. openssl is absent unless it is asked for.
stub_dir()
{
    local with_openssl="${1:-0}" count=""
    local dir="${BATS_TEST_TMPDIR}/bin"

    rm -rf "$dir"
    mkdir -p "$dir"
    write_stub "$dir" allowcred.awk 'exec sleep 3'
    write_stub "$dir" hostname 'echo node1'
    write_stub "$dir" logger 'echo "$@" >&2'
    write_stub "$dir" sleep 'exec /bin/sleep "$@"'
    if [ "$with_openssl" = 1 ]; then
        [ -n "${COUNT_REQUESTS:-}" ] && count="echo req >> '$COUNTER'"
        write_stub "$dir" openssl "[ \"\$1\" = req ] && { $count ; exit 1; }
exit 0"
    fi
    printf '%s\n' "$dir"
}

# Run getcert with only the stub directory on PATH. The timeout is the harness guard: a status
# of 124 means getcert never stopped.
run_getcert()
{
    local bin="$1" limit="$2" csr_timeout="$3"
    timeout -k 2 "$limit" env PATH="$bin" GETCERT_CSR_TIMEOUT="$csr_timeout" \
        /bin/bash "$GETCERT" 192.0.2.1:3001 2>&1 </dev/null
}

@test "getcert stops and names openssl when the image ships none" {
    # The el10 legacy image ships no openssl.
    run run_getcert "$(stub_dir 0)" 10 60
    [ "$status" -ne 124 ]
    [ "$status" -ne 0 ]
    [[ "$output" == *openssl* ]]
}

@test "getcert retries the certificate request, then gives up and names the key" {
    # doxcat writes /etc/xcat/certkey.pem in the background, so the first requests can fail.
    export COUNT_REQUESTS=1
    run run_getcert "$(stub_dir 1)" 30 5
    [ "$status" -ne 124 ]
    [ "$status" -ne 0 ]
    [[ "$output" == *certkey.pem* ]]

    tries=0
    [ -f "$COUNTER" ] && tries="$(grep -c req "$COUNTER")"
    [ "$tries" -gt 1 ]
}
