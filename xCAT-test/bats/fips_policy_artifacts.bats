#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    ROOT="$BATS_TEST_TMPDIR/source"
    local relative
    for relative in build-utils/sync-fips-policy build-utils/fips-policy.sh \
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
    [ "$status" -eq 0 ]
    run "$shell" -c '
        exec >"$RESULT" 2>&1
        . "$1"
        xcat_policy_probe
    ' fips-artifact-test "$ROOT/$library"
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
