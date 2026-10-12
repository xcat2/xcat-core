#!/usr/bin/env bats

load 'helpers/script_sandbox'

setup()
{
    setup_script_sandbox awk gawk
    local mawk
    if mawk=$(PATH=/usr/bin:/bin type -P mawk); then
        cp -L "$mawk" "$fixture/bin/awk"
    fi
    local source=${XCAT_TEST_GO_XCAT:-$(repo_path xCAT-server/share/xcat/tools/go-xcat)}
    [ -r "$source" ] || { echo "Required go-xcat is unreadable: $source" >&2; return 1; }
    sandbox+=(--ro-bind "$source" /run/go-xcat)
}

@test "the complete go-xcat script has valid Bash syntax" {
    run "${sandbox[@]}" bash -n /run/go-xcat
    [ "$status" -eq 0 ]
    [ "$output" = '' ]
}

detect_release()
{
    run "${sandbox[@]}" timeout 10 bash -c '
        source /run/go-xcat || exit
        distro=$(check_linux_distro) || exit
        version=$(check_linux_version) || exit
        printf "distro=%s\nversion=%s\n" "$distro" "$version"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'distro=%s\nversion=%s' "$1" "$2")" ]
}

@test "os-release precedes legacy release files" {
    printf 'NAME="Ubuntu"\nID="ubuntu"\nVERSION_ID="24.04"\n' >"$fixture/etc/os-release"
    printf 'Red Hat Enterprise Linux release 9.6 (Plow)\n' >"$fixture/etc/redhat-release"
    printf 'VERSION = 15.6\n' >"$fixture/etc/SuSE-release"
    detect_release ubuntu 24.04
}

@test "unquoted fields do not match ID_LIKE" {
    printf 'ID_LIKE=rhel\nID=rocky\nVERSION_ID=9.6\n' >"$fixture/etc/os-release"
    detect_release rocky 9.6
}

@test "single-quoted non-openEuler fields retain their current spelling" {
    printf "ID='debian'\nVERSION_ID='13'\n" >"$fixture/etc/os-release"
    detect_release "'debian'" "'13'"
}

@test "redhat-release supplies missing fields" {
    cp "$fixture/bin/gawk" "$fixture/bin/awk"
    printf 'Red Hat Enterprise Linux release 9.6 (Plow)\n' >"$fixture/etc/redhat-release"
    detect_release rhel 9.6
}

@test "SuSE-release supplies blank fields" {
    printf 'ID=\nVERSION_ID=\n' >"$fixture/etc/os-release"
    printf 'VERSION = 15.6\n' >"$fixture/etc/SuSE-release"
    detect_release sles 15.6
}

@test "SUSE-brand supplies fields absent from an empty os-release" {
    : >"$fixture/etc/os-release"
    printf 'VERSION = 12.5\n' >"$fixture/etc/SUSE-brand"
    detect_release sles 12.5
}

@test "missing release files produce empty fields quietly" {
    detect_release '' ''
}

@test "distro and version fall back independently" {
    printf 'VERSION_ID=10.1\n' >"$fixture/etc/os-release"
    printf 'Red Hat Enterprise Linux release 8.10 (Ootpa)\n' >"$fixture/etc/redhat-release"
    detect_release rhel 10.1
}

@test "redhat distro precedes both SUSE files" {
    printf 'VERSION_ID=10.1\n' >"$fixture/etc/os-release"
    printf 'Red Hat Enterprise Linux release 9.6 (Plow)\n' >"$fixture/etc/redhat-release"
    printf 'VERSION = 15.6\n' >"$fixture/etc/SuSE-release"
    printf 'VERSION = 12.5\n' >"$fixture/etc/SUSE-brand"
    detect_release rhel 10.1
}

@test "redhat version precedes both SUSE files" {
    cp "$fixture/bin/gawk" "$fixture/bin/awk"
    printf 'Red Hat Enterprise Linux release 9.6 (Plow)\n' >"$fixture/etc/redhat-release"
    printf 'VERSION = 15.6\n' >"$fixture/etc/SuSE-release"
    printf 'VERSION = 12.5\n' >"$fixture/etc/SUSE-brand"
    detect_release rhel 9.6
}

@test "SuSE-release precedes SUSE-brand" {
    printf 'VERSION = 15.6\n' >"$fixture/etc/SuSE-release"
    printf 'VERSION = 12.5\n' >"$fixture/etc/SUSE-brand"
    detect_release sles 15.6
}
