#!/usr/bin/env bats

load 'helpers/go_xcat'

setup()
{
    [ -n "$BATS_TEST_TMPDIR" ] || return 1
    fixture="$BATS_TEST_TMPDIR/repository"
    mkdir -p "$fixture/etc/yum.repos.d"
    COMMON_PRESENT=1
}

configure_repository()
{
    bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
        --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
        --bind "$fixture" /tmp/fixture --bind "$fixture/etc" /etc \
        --setenv COMMON_PRESENT "$COMMON_PRESENT" --chdir /tmp/fixture \
        bash /tmp/source/xCAT-test/bats/fixtures/go-xcat-common.sh "$@"
}

@test "an available remote common repository is installed and activated" {
    run configure_repository '' latest
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [ "$(cat "$fixture/download.log")" = 'https://repo.example.invalid/yum/latest/xcat-dep/common/repodata/repomd.xml' ]
    [ "$(cat "$fixture/ids")" = 'xcat-dep xcat-dep-common' ]
    repo="$fixture/etc/yum.repos.d/xcat-dep-common.repo"
    grep -Fxq '[xcat-dep-common]' "$repo"
    grep -Fxq 'baseurl=https://repo.example.invalid/yum/latest/xcat-dep/common' "$repo"
    grep -Fxq 'enabled=1' "$repo"
    grep -Fxq 'skip_if_unavailable=1' "$repo"
    grep -Fxq 'repo_gpgcheck=1' "$repo"
    grep -Fxq 'gpgcheck=1' "$repo"
    grep -Fxq 'gpgkey=https://repo.example.invalid/yum/latest/xcat-dep/common/repodata/repomd.xml.key' "$repo"
    [ "$(cat "$fixture/yum.log")" = 'clean metadata' ]
}

@test "a release without the remote common repository remains usable" {
    COMMON_PRESENT=0
    run configure_repository '' 2.18
    [ "$status" -eq 0 ]
    [ "$(cat "$fixture/ids")" = xcat-dep ]
    [ ! -e "$fixture/etc/yum.repos.d/xcat-dep-common.repo" ]
    [ ! -e "$fixture/yum.log" ]
}

@test "a custom repository file does not guess an unrelated common repository" {
    run configure_repository https://repo.example.invalid/custom/xcat-dep.repo latest
    [ "$status" -eq 0 ]
    [ ! -e "$fixture/download.log" ]
    [ ! -e "$fixture/etc/yum.repos.d/xcat-dep-common.repo" ]
    [ "$(cat "$fixture/ids")" = xcat-dep ]
}

@test "a local common repository is installed beside the distribution repository" {
    mkdir -p "$fixture/local/common/repodata"
    printf '<repomd/>\n' > "$fixture/local/common/repodata/repomd.xml"
    run configure_repository /tmp/fixture/local latest
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [ ! -e "$fixture/download.log" ]
    [ "$(cat "$fixture/ids")" = 'xcat-dep xcat-dep-common' ]
    grep -Fxq 'baseurl=file:///tmp/fixture/local/common' "$fixture/etc/yum.repos.d/xcat-dep-common.repo"
}

@test "an existing zypper common repository is retained without a new download" {
    mkdir -p "$fixture/etc/zypp/repos.d"
    printf '[xcat-dep-common]\n' > "$fixture/etc/zypp/repos.d/xcat-dep-common.repo"
    COMMON_PRESENT=0
    run configure_repository '' latest
    [ "$status" -eq 0 ]
    [ "$(cat "$fixture/ids")" = 'xcat-dep xcat-dep-common' ]
    [ "$(cat "$fixture/etc/zypp/repos.d/xcat-dep-common.repo")" = '[xcat-dep-common]' ]
}
