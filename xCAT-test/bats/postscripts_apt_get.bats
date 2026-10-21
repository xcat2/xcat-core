#!/usr/bin/env bats

load 'helpers/script_sandbox'

setup()
{
    postscripts=${XCAT_TEST_POSTSCRIPTS:-$(repo_path xCAT/postscripts)}
    PKGUTILS="$postscripts/xcatpkgutils.sh"
    local owner
    for owner in ospkgs otherpkgs xcatpkgutils.sh xcatpkgutils-loader.sh; do
        [ -r "$postscripts/$owner" ] || {
            echo "Required postscript is unreadable: $postscripts/$owner" >&2
            return 1
        }
    done
    APT_LOG="${BATS_TEST_TMPDIR:?bats-core 1.4 or newer is required}/apt-get.log"
    export APT_LOG
}

@test "the postscripts and package utilities ship executable" {
    [ -x "$postscripts/ospkgs" ]
    [ -x "$postscripts/otherpkgs" ]
    [ -x "$PKGUTILS" ]
}

@test "xcat_apt_get runs unattended and accepts unsigned xCAT repositories" {
    source "$PKGUTILS"
    apt-get() { printf '%s\t' "${DEBIAN_FRONTEND:-unset}" "$@" >"$APT_LOG"; }
    run xcat_apt_get -q install --no-install-recommends foo bar
    [ "$status" -eq 0 ]
    [ "$(cat "$APT_LOG")" = "$(printf '%s\t' noninteractive -y --allow-unauthenticated -q install --no-install-recommends foo bar)" ]
}

@test "xcat_apt_get returns the package manager status" {
    source "$PKGUTILS"
    apt-get() { return 100; }
    run xcat_apt_get upgrade
    [ "$status" -eq 100 ]
}

setup_postscript()
{
    setup_script_sandbox basename dirname cat cp expr grep ls mkdir rm uname wc sed stat diff
    mkdir -p "$fixture/etc/apt/sources.list.d"
    : >"$fixture/etc/apt/sources.list"
    local tool
    for tool in logger mount dpkg apt-cache apt-get; do
        cp "$(repo_path xCAT-test/bats/fixtures/package-command.sh)" "$fixture/bin/$tool"
        chmod +x "$fixture/bin/$tool"
    done
    sandbox+=(--ro-bind "$postscripts" /run/postscripts
        --setenv OSVER ubuntu24.04 --setenv ARCH x86_64 --setenv UPDATENODE 1
        --setenv NFSSERVER package-server --setenv HTTPPORT 80
        --setenv INSTALLDIR /install --setenv OTHERPKGDIR /install/other
        --setenv OSPKGDIR 'http://packages.example.invalid/ubuntu noble main'
        --setenv OSPKGS 'foo,bar' --setenv OTHERPKGS_INDEX 1
        --setenv OTHERPKGS1 'extra/foo,extra/bar'
        --setenv ENVLIST ACCEPT_EULA=ospkgs --setenv ENVLIST1 ACCEPT_EULA=otherpkgs)
}

run_postscript()
{
    local script=$1 expected=$2
    shift 2
    : >"$fixture/commands"
    run "${sandbox[@]}" "$@" timeout 15 bash "/run/postscripts/$script" </dev/null
    if [ "$status" -ne "$expected" ]; then
        printf 'Expected status %s, got %s\n%s\n' "$expected" "$status" "$output" >&2
        return 1
    fi
}

expect_call()
{
    printf '%s\t' "$@" >>"$fixture/expected"
    printf '\n' >>"$fixture/expected"
}

expect_ospkgs_calls()
{
    : >"$fixture/expected"
    expect_call apt-get unset unset x86_64 -y update
    expect_call apt-get noninteractive unset x86_64 -y --allow-unauthenticated -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade
    expect_call apt-get noninteractive ospkgs x86_64 -y --allow-unauthenticated -q install --no-install-recommends foo bar
}

expect_otherpkgs_calls()
{
    : >"$fixture/expected"
    expect_call apt-get unset unset x86_64 -y update
    expect_call apt-get noninteractive otherpkgs x86_64 -y --allow-unauthenticated -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef upgrade
    expect_call apt-get noninteractive otherpkgs x86_64 -y --allow-unauthenticated -q -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef install foo bar
}

@test "ospkgs upgrades and installs through the unattended helper" {
    setup_postscript
    run_postscript ospkgs 0
    expect_ospkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "ospkgs keeps upgrade failures while continuing the install" {
    setup_postscript
    run_postscript ospkgs 17 --setenv UPGRADE_STATUS 17
    expect_ospkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "ospkgs returns install failures" {
    setup_postscript
    run_postscript ospkgs 23 --setenv INSTALL_STATUS 23
    expect_ospkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "ospkgs preserves CUDA failure and restores ARCH before later removal" {
    setup_postscript
    run_postscript ospkgs 42 --setenv OSPKGS foo,bar,cuda-toolkit,-oldpkg --setenv CUDA_STATUS 42
    expect_ospkgs_calls
    expect_call apt-get noninteractive ospkgs unset -y --allow-unauthenticated -q install --no-install-recommends cuda-toolkit
    expect_call apt-get unset ospkgs x86_64 -y remove oldpkg
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "ospkgs reports CUDA failures for both RPM managers" {
    setup_postscript
    local manager
    for manager in yum dnf; do
        cp "$(repo_path xCAT-test/bats/fixtures/package-command.sh)" "$fixture/bin/$manager"
        chmod +x "$fixture/bin/$manager"
        run_postscript ospkgs 42 --setenv OSVER rhel9 --setenv OSPKGS cuda-toolkit,-oldpkg --setenv CUDA_STATUS 42
        : >"$fixture/expected"
        expect_call "$manager" unset unset x86_64 clean all
        expect_call "$manager" unset unset x86_64 -y upgrade
        expect_call "$manager" unset ospkgs unset -y install cuda-toolkit
        expect_call "$manager" unset ospkgs x86_64 -y remove oldpkg
        diff -u "$fixture/expected" "$fixture/commands"
        rm "$fixture/bin/$manager"
    done
}

@test "otherpkgs upgrades and installs through the unattended helper" {
    setup_postscript
    run_postscript otherpkgs 0
    expect_otherpkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "otherpkgs keeps upgrade failures while continuing the install" {
    setup_postscript
    run_postscript otherpkgs 17 --setenv UPGRADE_STATUS 17
    expect_otherpkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}

@test "otherpkgs returns install failures after the upgrade" {
    setup_postscript
    run_postscript otherpkgs 23 --setenv INSTALL_STATUS 23
    expect_otherpkgs_calls
    diff -u "$fixture/expected" "$fixture/commands"
}
