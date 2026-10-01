#!/usr/bin/env bats

load helpers/go_xcat

setup() {
    go_xcat_require_source
    source "$GO_XCAT_SOURCE"
    FIXTURE="$BATS_TEST_TMPDIR/repos"
    mkdir -p "$FIXTURE"
    TMP_DIR="$FIXTURE"
    GO_XCAT_DEFAULT_BASE_URL=https://packages.example.test/xcat
    GO_XCAT_ARCH=x86_64
    TEST_ID=openEuler
    TEST_VERSION='24.03 (LTS-SP3)'
    TEST_VERSION_ID=24.03
    PACKAGE_STATUS=0
    os_release_value() {
        case "$1" in
            ID) printf '%s\n' "$TEST_ID" ;;
            VERSION) printf '%s\n' "$TEST_VERSION" ;;
            VERSION_ID) printf '%s\n' "$TEST_VERSION_ID" ;;
            *) return 64 ;;
        esac
    }
    dnf() {
        if [[ $1 == repoquery ]]; then printf '%s\n' "${@: -1}"
        else printf 'dnf'; printf ' <%s>' "$@"; printf '\n'; fi
        return "$PACKAGE_STATUS"
    }
    yum() { printf 'yum'; printf ' <%s>' "$@"; printf '\n'; return "$PACKAGE_STATUS"; }
    download_file() { return 1; }
    add_repo_by_file() { cp "$1" "$FIXTURE/$2.repo"; }
    select_platform
}

select_platform() {
    GO_XCAT_LINUX_DISTRO="$(check_linux_distro)"
    GO_XCAT_LINUX_VERSION="$(check_linux_version)"
}

repositories() {
    select_platform || return
    add_xcat_core_repo_yum_or_zypper "${CORE_URL:-}" "${REPO_VERSION:-latest}" || return
    add_xcat_dep_repo_yum_or_zypper "${DEP_URL:-}" "${REPO_VERSION:-latest}"
}

@test "native repositories retain each release, service pack and architecture" {
    while IFS='|' read -r TEST_VERSION expected; do
        for GO_XCAT_ARCH in x86_64 ppc64le; do
            run repositories
            [ "$status" -eq 0 ]
            grep -Fx "baseurl=https://packages.example.test/xcat/yum/latest/xcat-core/openeuler$expected/$GO_XCAT_ARCH" "$FIXTURE/xcat-core.repo"
            grep -Fx "baseurl=https://packages.example.test/xcat/yum/latest/xcat-dep/openeuler$expected/$GO_XCAT_ARCH" "$FIXTURE/xcat-dep.repo"
        done
    done <<'CASES'
20.03 (LTS-SP4)|20.03sp4
22.03 (LTS-SP4)|22.03sp4
24.03 (LTS-SP1)|24.03sp1
24.03 (LTS-SP3)|24.03sp3
24.03 (LTS-SP4)|24.03sp4
24.03 (LTS)|24.03
CASES
}

@test "native identity and GA fallback" {
    for TEST_ID in openEuler openeuler "'openEuler'"; do
        run check_linux_distro
        [ "$status" -eq 0 ]
        [ "$output" = openeuler ]
    done
    TEST_VERSION="'24.03 (LTS-SP3)'"
    run check_linux_version
    [ "$status" -eq 0 ]
    [ "$output" = 24.03sp3 ]
    TEST_VERSION=''
    run check_linux_version
    [ "$status" -eq 0 ]
    [ "$output" = 24.03 ]
}

@test "invalid releases and architectures create no repositories" {
    for TEST_VERSION in 24.09 '25.03 (LTS)' '24.03 (LTS-SP0)' '24.03 (LTS-SP04)' '24.03 (LTS-SP3) trailing'; do
        run repositories
        [ "$status" -ne 0 ]
        [ ! -e "$FIXTURE/xcat-core.repo" ]
    done
    TEST_VERSION='24.03 (LTS-SP3)'
    GO_XCAT_ARCH=ppc64
    run repositories
    [ "$status" -ne 0 ]
    [ ! -e "$FIXTURE/xcat-core.repo" ]
}

@test "explicit URLs and development paths retain native layout" {
    CORE_URL=https://custom.example.test/native-core
    DEP_URL=https://custom.example.test/native-dep
    run repositories
    [ "$status" -eq 0 ]
    grep -Fx "baseurl=$CORE_URL" "$FIXTURE/xcat-core.repo"
    grep -Fx "baseurl=$DEP_URL/openeuler24.03sp3/x86_64" "$FIXTURE/xcat-dep.repo"
    unset CORE_URL DEP_URL
    REPO_VERSION=devel
    run repositories
    [ "$status" -eq 0 ]
    grep -Fx 'baseurl=https://packages.example.test/xcat/yum/devel/core-snap/openeuler24.03sp3/x86_64' "$FIXTURE/xcat-core.repo"
}

@test "offline native repositories still enforce package signatures" {
    mkdir -p "$FIXTURE/offline/core" "$FIXTURE/offline/dep/openeuler24.03sp3/x86_64"
    CORE_URL="file://$FIXTURE/offline/core"
    DEP_URL="file://$FIXTURE/offline/dep"
    run repositories
    [ "$status" -eq 0 ]
    grep -Fx gpgcheck=1 "$FIXTURE/xcat-core.repo"
    grep -Fx gpgcheck=1 "$FIXTURE/xcat-dep.repo"
}

@test "native package operations enforce signatures and propagate failure" {
    for command in install_packages_dnf install_packages_yum update_repo_dnf; do
        run "$command" -y xCAT
        [ "$status" -eq 0 ]
        [[ "$output" == *'<--setopt=*.gpgcheck=1>'* ]]
        [[ "$output" != *nogpgcheck* && "$output" != *strict=0* ]]
        if [[ $command != update_repo_dnf ]]; then
            [[ "$output" == *'<install> <initscripts> <xCAT>'* ]]
            [[ $command != install_packages_dnf || "$output" == *'<--setopt=strict=1>'* ]]
            PACKAGE_STATUS=37
            run "$command" -y xCAT
            [ "$status" -eq 37 ]
            PACKAGE_STATUS=0
        fi
    done
}

@test "EL and SLES repository selection retains existing behavior" {
    while read -r TEST_ID TEST_VERSION_ID expected; do
        run repositories
        [ "$status" -eq 0 ]
        grep -Fx 'baseurl=https://packages.example.test/xcat/yum/latest/xcat-core' "$FIXTURE/xcat-core.repo"
        grep -Fx "baseurl=https://packages.example.test/xcat/yum/latest/xcat-dep/$expected/x86_64" "$FIXTURE/xcat-dep.repo"
    done <<'CASES'
rocky 9.6 rh9
rhel 10.1 rh10
sles 15.6 sles15
CASES
    TEST_ID=rhel TEST_VERSION_ID=10.1
    select_platform
    run install_packages_dnf -y xCAT
    [ "$status" -eq 0 ]
    [[ "$output" == *'<--nogpgcheck> <--setopt=strict=0>'* ]]
}

@test "repository replacement selects DNF when yum is absent" {
    unset -f yum
    type() { [[ $1 != yum ]] && builtin type "$@"; }
    grep() { return 1; }
    xargs() { cat >/dev/null; }
    mv() { return 0; }
    run remove_repo_yum xcat-core
    [ "$status" -eq 0 ]
    [ "$output" = 'dnf <clean> <metadata>' ]
}
