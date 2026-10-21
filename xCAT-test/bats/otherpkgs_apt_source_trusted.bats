#!/usr/bin/env bats
#
# The otherpkgs postscript stages an apt repository that carries a Packages file and no Release.
# apt refuses an unsigned repository outright -- "does not have a Release file" -- so the
# postscript's apt-cache show finds nothing, it deletes the source line it has just written, and
# the package is never installed. On a service node that package is xcatsn.
#
# This drives apt against a real flat repository in a scratch tree, with both spellings of the
# source line, and then holds the postscript to the one apt accepts.

load 'helpers/shell_source'

setup()
{
    command -v apt-get >/dev/null 2>&1 || skip 'apt-get is required'
    command -v dpkg-scanpackages >/dev/null 2>&1 || skip 'dpkg-scanpackages is required'

    REPO="${BATS_TEST_TMPDIR}/repo"
    ROOT="${BATS_TEST_TMPDIR}/aptroot"
    mkdir -p "$REPO" "$ROOT/etc/apt/sources.list.d" "$ROOT/var/lib/apt/lists/partial" \
             "$ROOT/var/lib/dpkg" "$ROOT/var/cache/apt/archives/partial"
    : >"$ROOT/var/lib/dpkg/status"

    # A minimal binary package, so the index describes something real.
    local build="${BATS_TEST_TMPDIR}/pkg/xcatsn"
    mkdir -p "$build/DEBIAN"
    printf 'Package: xcatsn\nVersion: 2.20.0\nArchitecture: all\nMaintainer: t <t@example.invalid>\nDescription: probe\n' \
        >"$build/DEBIAN/control"
    dpkg-deb --build -Znone "$build" "$REPO/xcatsn_2.20.0_all.deb" >/dev/null
    ( cd "$REPO" && dpkg-scanpackages -m . >Packages 2>/dev/null )
}

# Resolve xcatsn through apt with the given source line. Sets OUT and STATUS.
resolve()
{
    printf '%s\n' "$1" >"$ROOT/etc/apt/sources.list.d/probe.list"
    apt-get -o "Dir=$ROOT" -o "Dir::State::status=$ROOT/var/lib/dpkg/status" \
            -o "Dir::Etc::sourcelist=$ROOT/etc/apt/sources.list.d/probe.list" \
            -o Dir::Etc::sourceparts=/dev/null -o APT::Get::List-Cleanup=0 \
            update >/dev/null 2>&1 || true   # an untrusted source makes update itself exit 100,
                                             # and that refusal is what this test measures. Under
                                             # bats' set -e an unguarded failure here aborts the
                                             # function before apt-cache runs, so the test could
                                             # only ever pass where apt-get is absent and it skips.
    OUT="$(apt-cache -o "Dir=$ROOT" -o "Dir::State::status=$ROOT/var/lib/dpkg/status" \
            show xcatsn 2>&1)" && STATUS=0 || STATUS=$?
}

@test "apt refuses the source line without trusted=yes, so the package cannot be found" {
    resolve "deb file://$REPO ./"
    [ "$STATUS" -ne 0 ]
    [[ "$OUT" != *"Package: xcatsn"* ]]
}

@test "apt resolves the package when the source line is trusted" {
    resolve "deb [trusted=yes] file://$REPO ./"
    [ "$STATUS" -eq 0 ]
    [[ "$OUT" == *"Package: xcatsn"* ]]
}
