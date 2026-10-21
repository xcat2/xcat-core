#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    : "${BATS_TEST_TMPDIR:?Bats 1.4 or newer is required}"
    ROOT="$BATS_TEST_TMPDIR/source"
    local relative
    for relative in build-utils/sync-fips-policy build-utils/fips-policy.sh \
        build-utils/lib/XCAT/BuildUtils.pm \
        xCAT-genesis-scripts/usr/lib/xcat/fips.sh xCAT/postscripts/xcatlib.sh; do
        mkdir -p "$ROOT/$(dirname "$relative")"
        cp "$(repo_path "$relative")" "$ROOT/$relative"
    done
    printf '\nxcat_policy_probe() { printf canonical; }\n' >>"$ROOT/build-utils/fips-policy.sh"
    export RESULT="$BATS_TEST_TMPDIR/result"
}

check_generated_policy()
{
    local shell="$1" library="$2"
    run perl "$ROOT/build-utils/sync-fips-policy" --write
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    run "$shell" -c '
        exec >"$RESULT" 2>&1
        . "$1"
        xcat_policy_probe
    ' fips-artifact-test "$ROOT/$library"
    printf '%s\n' "$output"
    if [ -f "$RESULT" ]; then
        cat "$RESULT"
    fi
    [ "$status" -eq 0 ]
    printf canonical >"$BATS_TEST_TMPDIR/expected-result"
    cmp "$BATS_TEST_TMPDIR/expected-result" "$RESULT"
}

@test "generated Genesis policy runs in sh" {
    check_generated_policy sh xCAT-genesis-scripts/usr/lib/xcat/fips.sh
}

@test "generated Cumulus policy runs in bash" {
    check_generated_policy bash xCAT/postscripts/xcatlib.sh
}

@test "policy check reports stale artifacts without changing them" {
    run perl "$ROOT/build-utils/sync-fips-policy" --check
    printf '%s\n' "$output"
    [ "$status" -eq 1 ]
    local expected
    expected=$(printf '%s is out of date; run build-utils/sync-fips-policy --write\n' \
        xCAT-genesis-scripts/usr/lib/xcat/fips.sh xCAT/postscripts/xcatlib.sh)
    [ "$output" = "$expected" ]
    cmp "$(repo_path xCAT-genesis-scripts/usr/lib/xcat/fips.sh)" \
        "$ROOT/xCAT-genesis-scripts/usr/lib/xcat/fips.sh"
    cmp "$(repo_path xCAT/postscripts/xcatlib.sh)" "$ROOT/xCAT/postscripts/xcatlib.sh"
}

@test "policy check succeeds quietly after generation" {
    run perl "$ROOT/build-utils/sync-fips-policy" --write
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    run perl "$ROOT/build-utils/sync-fips-policy" --check
    printf '%s\n' "$output"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "policy commands reject invalid input without changing artifacts" {
    printf '%s' no-final-newline >"$ROOT/build-utils/fips-policy.sh"
    local mode
    for mode in --check --write; do
        run perl "$ROOT/build-utils/sync-fips-policy" "$mode"
        printf '%s\n' "$output"
        [ "$status" -ne 0 ]
        [[ "$output" == *"FIPS policy must end with a newline"* ]]
        cmp "$(repo_path xCAT-genesis-scripts/usr/lib/xcat/fips.sh)" \
            "$ROOT/xCAT-genesis-scripts/usr/lib/xcat/fips.sh"
        cmp "$(repo_path xCAT/postscripts/xcatlib.sh)" "$ROOT/xCAT/postscripts/xcatlib.sh"
    done
}
