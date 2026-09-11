#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    PKGUTILS="$(repo_path 'xCAT/postscripts/xcatpkgutils.sh')"
    OSPKGS="$(repo_path 'xCAT/postscripts/ospkgs')"
    OTHERPKGS="$(repo_path 'xCAT/postscripts/otherpkgs')"
    [ -r "$PKGUTILS" ] || skip "$PKGUTILS is required"
    [ -r "$OSPKGS" ] || skip "$OSPKGS is required"
    [ -r "$OTHERPKGS" ] || skip "$OTHERPKGS is required"
    APT_LOG="${BATS_TEST_TMPDIR}/apt-get.log"
    export PKGUTILS OSPKGS OTHERPKGS APT_LOG
}

# Every apt-get call is recorded as "<DEBIAN_FRONTEND>|<arguments>" and answers with APT_STATUS.
shadow_apt_get()
{
    apt-get()
    {
        printf '%s|%s\n' "${DEBIAN_FRONTEND:-unset}" "$*" >>"$APT_LOG"
        return "${APT_STATUS:-0}"
    }
}

apt_call()
{
    sed -n "${1}p" "$APT_LOG"
}

apt_calls()
{
    wc -l <"$APT_LOG" | tr -d ' '
}

run_ospkgs_apt_block()
{
    local block
    block="$(extract_line_range "$OSPKGS" '# upgrade existing packages' '# remove packages')" || return 99
    local ENVLIST="" groups="" pkgs=" foo bar" cudapkgs="${1:-}" RETURNVAL=0 ARCH=x86_64
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

run_otherpkgs_apt_line()
{
    local line
    line="$(extract_first_matching_line "$OTHERPKGS" "$1")" || return 99
    local envlist="" repo_pkgs="foo bar" result=""
    eval "$line"
    printf 'R=%s\n' "$?"
    printf '%s\n' "$result"
}

@test "the postscripts and the package utilities ship executable" {
    [ -x "$OSPKGS" ]
    [ -x "$OTHERPKGS" ]
    [ -x "$PKGUTILS" ]
}

@test "xcat_apt_get runs apt-get unattended and accepts the unsigned xCAT repositories" {
    source "$PKGUTILS"
    shadow_apt_get

    run xcat_apt_get -q install --no-install-recommends foo bar
    [ "$status" -eq 0 ]
    [ "$(apt_call 1)" = "noninteractive|-y --allow-unauthenticated -q install --no-install-recommends foo bar" ]
    [ "$(apt_calls)" -eq 1 ]
}

@test "xcat_apt_get returns the apt-get status" {
    source "$PKGUTILS"
    shadow_apt_get

    APT_STATUS=100 run xcat_apt_get upgrade
    [ "$status" -eq 100 ]
}

@test "a pkglist environment prefix reaches apt-get through the eval the postscripts use" {
    source "$PKGUTILS"
    apt-get()
    {
        printf '%s\n' "${ACCEPT_EULA:-unset}" >>"$APT_LOG"
    }
    local ENVLIST="ACCEPT_EULA=y"

    run eval "$ENVLIST xcat_apt_get -q install foo"
    [ "$status" -eq 0 ]
    [ "$(apt_call 1)" = "y" ]
}

@test "ospkgs upgrades and installs through xcat_apt_get without --force-yes" {
    source "$PKGUTILS"
    shadow_apt_get

    run run_ospkgs_apt_block
    [ "$status" -eq 0 ]
    [[ "$output" == *'RETURNVAL=0'* ]]
    [ "$(apt_call 1 | cut -d'|' -f2)" = "-y update" ]
    [ "$(apt_call 2)" = "noninteractive|-y --allow-unauthenticated -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade" ]
    [ "$(apt_call 3)" = "noninteractive|-y --allow-unauthenticated -q install --no-install-recommends foo bar" ]
    [ "$(apt_calls)" -eq 3 ]
    ! grep -q -- '--force-yes' "$APT_LOG"
}

@test "ospkgs keeps the apt-get failure status and still runs the later steps" {
    source "$PKGUTILS"
    shadow_apt_get

    APT_STATUS=100 run run_ospkgs_apt_block
    [ "$status" -eq 0 ]
    [[ "$output" == *'RETURNVAL=100'* ]]
    [ "$(apt_calls)" -eq 3 ]
}

@test "ospkgs reports a failed cuda package install" {
    source "$PKGUTILS"
    apt-get()
    {
        printf '%s|%s\n' "${DEBIAN_FRONTEND:-unset}" "$*" >>"$APT_LOG"
        case "$*" in
        *cuda*) return 100 ;;
        esac
        return 0
    }

    run run_ospkgs_apt_block " cuda-toolkit"
    [ "$status" -eq 0 ]
    [[ "$output" == *'RETURNVAL=100'* ]]
    [ "$(apt_call 4)" = "noninteractive|-y --allow-unauthenticated -q install --no-install-recommends cuda-toolkit" ]
    [ "$(apt_calls)" -eq 4 ]
}

run_ospkgs_rpm_cuda_block()
{
    local block tail="${BATS_TEST_TMPDIR}/ospkgs-rpm-tail"
    sed -n '/#install cuda package if any/,$p' "$OSPKGS" >"$tail"
    block="$(extract_shell_if_block "$tail" 'if [ -n "$cudapkgs" ]; then')" || return 99
    local ENVLIST="" yumcmd=fake_dnf cudapkgs=" cuda-toolkit" RETURNVAL=0 ARCH=x86_64 debug=0 log_label=ospkgs
    logger() { :; }
    fake_dnf()
    {
        printf '%s\n' "$*" >>"$APT_LOG"
        return 100
    }
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

@test "ospkgs reports a failed cuda package install on yum and dnf nodes" {
    run run_ospkgs_rpm_cuda_block
    [ "$status" -eq 0 ]
    [[ "$output" == *'RETURNVAL=100'* ]]
    [ "$(apt_call 1)" = "-y install cuda-toolkit" ]
    [ "$(apt_calls)" -eq 1 ]
}

@test "otherpkgs upgrades through xcat_apt_get without --force-yes" {
    source "$PKGUTILS"
    shadow_apt_get

    run run_otherpkgs_apt_line 'result=`eval [$]envlist .*Dpkg::Options.* upgrade 2>&1`'
    [ "$status" -eq 0 ]
    [[ "$output" == *'R=0'* ]]
    [ "$(apt_call 1)" = "noninteractive|-y --allow-unauthenticated -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade" ]
    [ "$(apt_calls)" -eq 1 ]
}

@test "otherpkgs installs through xcat_apt_get without --force-yes" {
    source "$PKGUTILS"
    shadow_apt_get

    run run_otherpkgs_apt_line 'result=`eval [$]envlist .*Dpkg::Options.* install [$]repo_pkgs 2>&1`'
    [ "$status" -eq 0 ]
    [[ "$output" == *'R=0'* ]]
    [ "$(apt_call 1)" = "noninteractive|-y --allow-unauthenticated -q -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef install foo bar" ]
    [ "$(apt_calls)" -eq 1 ]
}
