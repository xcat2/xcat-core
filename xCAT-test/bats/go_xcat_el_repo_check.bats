#!/usr/bin/env bats

load 'helpers/go_xcat'

setup()
{
    go_xcat_require_source
    export CALLS="${BATS_TEST_TMPDIR}/calls"
    export GO_XCAT_ARCH=x86_64
    export GO_XCAT_LINUX_DISTRO=rocky
    export GO_XCAT_LINUX_VERSION=10.2
    export EPEL_HAS=1
    export CRB_HAS=1
    export QUERY_FAIL=0
    export QUERY_WARNS=0
    export SOURCE_ONLY=0
    export ENTRY=check
}

run_el_repo_check()
{
    rm -f "$CALLS"

    go_xcat_load_functions \
        repo_carries \
        el_epel_and_crb_check \
        install_packages_dnf \
        install_packages_yum

    EL_EPEL_TEST_RPM=perl-Crypt-CBC
    EL_CRB_TEST_RPM=perl-IO-Tty

    dnf()
    {
        echo "$*" >>"$CALLS"
        if [[ ${QUERY_FAIL:-0} == 1 ]]; then
            echo "Error: Failed to download metadata for repo 'epel'" >&2
            return 1
        fi
        [[ ${QUERY_WARNS:-0} == 1 ]] && echo "Warning: repository 'extras' metadata is stale" >&2

        local has=0
        case "$*" in
            *perl-Crypt-CBC*) has="$EPEL_HAS" ;;
            *perl-IO-Tty*)    has="$CRB_HAS" ;;
        esac

        [[ ${SOURCE_ONLY:-0} == 1 && "$*" != *"--arch"* ]] && has=1
        case "$1" in
            repoquery) [[ $has == 1 ]] && { echo "${@: -1}"; echo "${@: -1}"; }; return 0 ;;
            list)      [[ $has == 1 ]] && return 0; return 1 ;;
        esac
        return 0
    }

    yum()
    {
        dnf "$@"
    }

    case "${ENTRY:-check}" in
        dnf) install_packages_dnf -y xCAT ;;
        yum) install_packages_yum -y xCAT ;;
        *)   el_epel_and_crb_check dnf ;;
    esac
}

@test "EL9 with EPEL and CRB passes after probing binary repositories" {
    export GO_XCAT_LINUX_VERSION=9.5

    run run_el_repo_check
    [ "$status" -eq 0 ]
    probes="$(joined_file_lines "$CALLS")"
    [[ "$probes" =~ perl-Crypt-CBC.*\;.*perl-IO-Tty ]]
    [[ "$probes" =~ ^repoquery\  ]]
    [[ "$probes" =~ --arch\ x86_64,noarch ]]
}

@test "EL9 without EPEL stops and names the EL9 release package" {
    export GO_XCAT_LINUX_VERSION=9.5
    export EPEL_HAS=0

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ epel-release-latest-9\.noarch ]]
}

@test "EL10 with EPEL and CRB passes after probing both repositories" {
    run run_el_repo_check
    [ "$status" -eq 0 ]
    probes="$(joined_file_lines "$CALLS")"
    [[ "$probes" =~ perl-Crypt-CBC.*\;.*perl-IO-Tty ]]
}

@test "EL10 without EPEL stops with the EL10 EPEL release package" {
    export EPEL_HAS=0

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ requires\ EPEL\ repository ]]
    [[ "$output" =~ epel-release-latest-10\.noarch ]]
}

@test "EL10 without CRB stops with current CRB guidance" {
    export GO_XCAT_LINUX_DISTRO=rhel
    export CRB_HAS=0

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ requires\ CRB\ repository ]]
    [[ "$output" =~ "'dnf update epel-release' and then 'crb enable'" ]]
    [[ ! "$output" =~ gpgcheck=0|centos-crb|subscription-manager ]]
}

@test "a source repository does not stand in for the binary one" {
    export EPEL_HAS=0
    export SOURCE_ONLY=1

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ requires\ EPEL\ repository ]]
}

@test "Oracle Linux 10 without CRB names its CodeReady Builder command" {
    export GO_XCAT_LINUX_DISTRO=ol
    export GO_XCAT_LINUX_VERSION=10.1
    export CRB_HAS=0

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ dnf\ config-manager\ --enable\ ol10_codeready_builder ]]
}

@test "a failed repository query stops with the package manager error" {
    export QUERY_FAIL=1

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ Failed\ to\ download\ metadata ]]
    [[ ! "$output" =~ requires\ EPEL\ repository ]]
}

@test "a warning on stderr does not stand in for a package" {
    export EPEL_HAS=0
    export QUERY_WARNS=1

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ requires\ EPEL\ repository ]]
}

@test "a warning beside a real match does not fail the check" {
    export QUERY_WARNS=1

    run run_el_repo_check
    [ "$status" -eq 0 ]
}

@test "CentOS Stream 10, which reports the major version alone, is checked" {
    export GO_XCAT_LINUX_DISTRO=centos
    export GO_XCAT_LINUX_VERSION=10
    export EPEL_HAS=0
    export CRB_HAS=0

    run run_el_repo_check
    [ "$status" -eq 1 ]
    [[ "$output" =~ requires\ EPEL\ repository ]]
}

@test "EL8 and Fedora are not checked" {
    export GO_XCAT_LINUX_VERSION=8.10
    export EPEL_HAS=0
    export CRB_HAS=0

    run run_el_repo_check
    [ "$status" -eq 0 ]
    [ "$(joined_file_lines "$CALLS")" = "" ]

    export GO_XCAT_LINUX_DISTRO=fedora
    export GO_XCAT_LINUX_VERSION=42

    run run_el_repo_check
    [ "$status" -eq 0 ]
}

@test "dnf and yum installer paths run the check before installing" {
    for entry in dnf yum; do
        export ENTRY="$entry"
        export EPEL_HAS=0
        export CRB_HAS=1

        run run_el_repo_check
        [ "$status" -eq 1 ]
        [[ "$output" =~ requires\ EPEL\ repository ]]
        probes="$(joined_file_lines "$CALLS")"
        [[ ! "$probes" =~ install ]]

        export EPEL_HAS=1
        export CRB_HAS=1

        run run_el_repo_check
        [ "$status" -eq 0 ]
        probes="$(joined_file_lines "$CALLS")"
        [[ "$probes" =~ perl-IO-Tty.*\;.*install\ initscripts.*\;.*install\ xCAT ]]
    done
}
