#!/usr/bin/env bats
#
# go-xcat trusts the xcat.org apt key without apt-key, which apt 3 does not ship. It installs
# the key as a binary keyring, which apt before 1.4 needs, and a complete uninstall removes it
# with the repository files.

load 'helpers/go_xcat'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'repository checks require Linux namespaces'
    command -v bwrap >/dev/null || skip 'bwrap is required'
    go_xcat_require_source
    [ -n "$BATS_TEST_TMPDIR" ] || return 1
    fixture="$BATS_TEST_TMPDIR/apt"
    mkdir -p "$fixture/etc/apt/sources.list.d"
    printf 'DISTRIB_CODENAME=resolute\n' >"$fixture/etc/lsb-release"
    # Two armored blocks, as xcat.org publishes, each holding a public key packet (0x99).
    printf '\231\000\002ab\231\000\002cd' >"$fixture/keyring.gpg"
    {
        armored_block "$(printf '\231\000\002ab' | base64)" 'Version: GnuPG v1'
        armored_block "$(printf '\231\000\002cd' | base64)"
    } >"$fixture/key.asc"
}

# Print an armored public key block with the base64 body $1 and the optional header $2.
armored_block()
{
    printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\n'
    [ -z "$2" ] || printf '%s\n' "$2"
    printf '\n%s\n=AAAA\n-----END PGP PUBLIC KEY BLOCK-----\n' "$1"
}

run_go_xcat_apt()
{
    # Debian reaches awk through /etc/alternatives, which the fixture /etc hides.
    local -a alternatives=()
    [ -d /etc/alternatives ] && alternatives=(--ro-bind /etc/alternatives /etc/alternatives)
    bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
        --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
        --ro-bind "$GO_XCAT_SOURCE" /tmp/go-xcat \
        --bind "$fixture" /tmp/fixture --bind "$fixture/etc" /etc "${alternatives[@]}" \
        --chdir /tmp/fixture \
        bash /tmp/source/xCAT-test/bats/fixtures/go-xcat-apt.sh "$@"
}

@test "the default xcat-core repository trusts the xCAT key as a binary keyring" {
    run run_go_xcat_apt add
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [ ! -e "$fixture/apt-key.log" ]
    [ "$(cat "$fixture/download.log")" = 'https://repo.example.invalid/apt/apt.key' ]
    key="$fixture/etc/apt/trusted.gpg.d/xcat.gpg"
    cmp "$fixture/keyring.gpg" "$key"
    [ "$(stat -c %a "$key")" = 644 ]
    [ "$(cat "$fixture/etc/apt/sources.list.d/xcat-core.list")" = \
        'deb [arch=riscv64] https://repo.example.invalid/apt/latest/xcat-core resolute main' ]
}

@test "a download that holds no public key keeps the installed key and stops" {
    mkdir -p "$fixture/etc/apt/trusted.gpg.d"
    key="$fixture/etc/apt/trusted.gpg.d/xcat.gpg"
    local -a downloads=(
        ''
        '<html>Not Found</html>'
        '-----BEGIN PGP PUBLIC KEY BLOCK-----'
        "$(armored_block '!!!!')"
        "$(armored_block "$(printf '\264\001a' | base64)")"
        "$(printf -- '-----BEGIN PGP PUBLIC KEY BLOCK-----\n\nmQEN')"
        "$(head -n 9 "$fixture/key.asc")"
    )
    for download in "${downloads[@]}"; do
        cp "$fixture/keyring.gpg" "$key"
        printf '%s\n' "$download" >"$fixture/key.asc"
        run run_go_xcat_apt add
        [ "$status" -ne 0 ] || { printf 'accepted %s\n' "$download"; return 1; }
        grep -Fq 'import xcat apt key failed' <<<"$output"
        cmp "$fixture/keyring.gpg" "$key"
        [ ! -e "$fixture/etc/apt/sources.list.d/xcat-core.list" ]
    done
}

@test "a complete uninstall removes the xCAT key and keeps other keys" {
    mkdir -p "$fixture/etc/apt/trusted.gpg.d"
    cp "$fixture/keyring.gpg" "$fixture/etc/apt/trusted.gpg.d/xcat.gpg"
    cp "$fixture/keyring.gpg" "$fixture/etc/apt/trusted.gpg.d/other.gpg"
    run run_go_xcat_apt trash
    [ ! -e "$fixture/etc/apt/trusted.gpg.d/xcat.gpg" ]
    [ -e "$fixture/etc/apt/trusted.gpg.d/other.gpg" ]
}
