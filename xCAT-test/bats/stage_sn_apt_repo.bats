#!/usr/bin/env bats
#
# Drive stage_sn_apt_repo.sh, which writes the flat apt index a Debian service node installs
# from. The otherpkgs postscript writes "deb <type>://<otherpkgdir>/<directory> ./", and that
# trailing "./" makes apt read <directory>/Packages and resolve each Filename against it.
#
# dpkg-scanpackages is stubbed, so the test measures the directory selection and the guards and
# not dpkg-dev.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/installation/stage_sn_apt_repo.sh')"
    REPO="${BATS_TEST_TMPDIR}/repo"
    BIN="${BATS_TEST_TMPDIR}/bin"
    RECORD="${BATS_TEST_TMPDIR}/scanned"
    mkdir -p "$REPO" "$BIN"

    # Record the directory it was asked to scan, and emit one stanza per deb found under it.
    cat >"$BIN/dpkg-scanpackages" <<STUB
#!/bin/sh
[ "\$1" = "-m" ] && shift
printf '%s\n' "\$1" >>"$RECORD"
find "\$1" -name '*.deb' | while read -r d; do
    printf 'Package: %s\nFilename: %s\n\n' "\$(basename "\$d" .deb)" "\$d"
done
exit 0
STUB
    chmod 0755 "$BIN/dpkg-scanpackages"
    export PATH="$BIN:$PATH"
}

deb()
{
    mkdir -p "$(dirname "$REPO/$1")"
    : >"$REPO/$1"
}

scanned()
{
    read_file_or_empty "$RECORD"
}

@test "a reprepro tree is indexed whole, so the pool is reachable from the flat index" {
    deb pool/main/x/xcat/xcatsn_2.20.0_amd64.deb
    deb pool/main/x/xcat/xcat-client_2.20.0_all.deb

    run "$SCRIPT" "$REPO"
    [ "$status" -eq 0 ]
    [ "$(scanned)" = "." ]
    [[ "$output" == *"2 package(s) indexed"* ]]
    grep -q '^Package: xcatsn_2.20.0_amd64$' "$REPO/Packages"
    [ -s "$REPO/Packages.gz" ]
}

@test "a tree with one directory per release is indexed from the directory the os version names" {
    deb ubuntu22.04/conserver-xcat_8.2.1-1_amd64.deb
    deb ubuntu24.04/conserver-xcat_8.2.1-1_amd64.deb
    deb ubuntu26.04/conserver-xcat_8.2.1-1_amd64.deb

    run "$SCRIPT" "$REPO" ubuntu24.04.4
    [ "$status" -eq 0 ]
    [ "$(scanned)" = "ubuntu24.04" ]
    [[ "$output" == *"1 package(s) indexed"* ]]
}

@test "an os version no directory matches falls back to the whole tree" {
    deb ubuntu22.04/conserver-xcat_8.2.1-1_amd64.deb
    deb ubuntu26.04/conserver-xcat_8.2.1-1_amd64.deb

    run "$SCRIPT" "$REPO" ubuntu24.04.4
    [ "$status" -eq 0 ]
    [ "$(scanned)" = "." ]
}

@test "a tree with no deb fails instead of writing an empty index" {
    mkdir -p "$REPO/pool"

    run "$SCRIPT" "$REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"no deb package under"* ]]
    [ ! -e "$REPO/Packages" ]
}

@test "a failing dpkg-scanpackages fails the step and leaves no index" {
    deb pool/main/x/xcat/xcatsn_2.20.0_amd64.deb
    printf '#!/bin/sh\necho "cannot read" >&2\nexit 2\n' >"$BIN/dpkg-scanpackages"
    chmod 0755 "$BIN/dpkg-scanpackages"

    run "$SCRIPT" "$REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"dpkg-scanpackages failed"* ]]
    [ ! -e "$REPO/Packages" ]
}

@test "a directory that does not exist fails" {
    run "$SCRIPT" "${BATS_TEST_TMPDIR}/absent"
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a directory"* ]]
}

@test "no argument fails" {
    run "$SCRIPT"
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage:"* ]]
}
