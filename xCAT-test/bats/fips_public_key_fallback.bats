#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    : "${BATS_TEST_TMPDIR:?Bats 1.4 or newer is required}"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat >"$BATS_TEST_TMPDIR/bin/openssl" <<'SH'
#!/bin/sh
exporter=$1
shift
printf '%s\n' "$exporter" >> "$CALLS"
printf 'openssl' >> "$INVOCATIONS"
printf ' <%s>' "$exporter" "$@" >> "$INVOCATIONS"
printf '\n' >> "$INVOCATIONS"
input=
public=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        -in) [ "$#" -ge 2 ] || exit 64; input=$2; shift 2 ;;
        -pubout) public=1; shift ;;
        *) exit 64 ;;
    esac
done
if [ "$input" != "$KEY" ] || [ "$public" -ne 1 ]; then
    printf 'rejected: expected -in with the requested key and -pubout\n' >> "$INVOCATIONS"
    exit 64
fi
if [ "$exporter" = "$ACCEPT" ]; then
    printf 'public key\n'
    exit 0
fi
printf '%s failed\n' "$exporter" >&2
exit 73
SH
    chmod 0755 "$BATS_TEST_TMPDIR/bin/openssl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export CALLS="$BATS_TEST_TMPDIR/calls"
    export INVOCATIONS="$BATS_TEST_TMPDIR/invocations"
    export RESULT="$BATS_TEST_TMPDIR/result"
    export KEY="$BATS_TEST_TMPDIR/unused key.pem"
}

check_fallback()
{
    local shell="$1" library="$2" accept="$3" calls="$4" mode
    local expected_status=0
    export ACCEPT="$accept"
    printf '%s' "$calls" >"$BATS_TEST_TMPDIR/expected-calls"
    if [ "$accept" = none ]; then
        expected_status=73
        printf 'ec failed\n' >"$BATS_TEST_TMPDIR/expected-result"
    else
        printf 'public key\n' >"$BATS_TEST_TMPDIR/expected-result"
    fi
    for mode in 0 1; do
        printf '%s policy mode %s\n' "$library" "$mode"
        : >"$CALLS"
        : >"$INVOCATIONS"
        run "$shell" -c '
            exec >"$RESULT" 2>&1
            . "$1"
            xcat_discovery_public_key "$2" "$3"
        ' fips-fallback-test "$(repo_path "$library")" "$mode" "$KEY"
        printf '%s\n' "$output"
        if [ -f "$RESULT" ]; then
            cat "$RESULT"
        fi
        cat "$INVOCATIONS"
        printf 'exporters:\n'
        cat "$CALLS"
        [ "$status" -eq "$expected_status" ]
        cmp "$BATS_TEST_TMPDIR/expected-result" "$RESULT"
        cmp "$BATS_TEST_TMPDIR/expected-calls" "$CALLS"
    done
}

@test "Genesis exports through pkey without trying fallbacks" {
    check_fallback sh xCAT-genesis-scripts/usr/lib/xcat/fips.sh pkey $'pkey\n'
}

@test "Genesis falls back to rsa and stops on success" {
    check_fallback sh xCAT-genesis-scripts/usr/lib/xcat/fips.sh rsa $'pkey\nrsa\n'
}

@test "Genesis falls back to ec and hides earlier errors" {
    check_fallback sh xCAT-genesis-scripts/usr/lib/xcat/fips.sh ec $'pkey\nrsa\nec\n'
}

@test "Genesis returns the final error when all exporters fail" {
    check_fallback sh xCAT-genesis-scripts/usr/lib/xcat/fips.sh none $'pkey\nrsa\nec\n'
}

@test "Cumulus exports through pkey without trying fallbacks" {
    check_fallback bash xCAT/postscripts/xcatlib.sh pkey $'pkey\n'
}

@test "Cumulus falls back to rsa and stops on success" {
    check_fallback bash xCAT/postscripts/xcatlib.sh rsa $'pkey\nrsa\n'
}

@test "Cumulus falls back to ec and hides earlier errors" {
    check_fallback bash xCAT/postscripts/xcatlib.sh ec $'pkey\nrsa\nec\n'
}

@test "Cumulus returns the final error when all exporters fail" {
    check_fallback bash xCAT/postscripts/xcatlib.sh none $'pkey\nrsa\nec\n'
}
