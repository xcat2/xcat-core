#!/usr/bin/env bats
#
# `go-xcat uninstall` hands GO_XCAT_UNINSTALL_LIST to the package manager. That list names
# packages xCAT stopped producing -- xCAT-genesis-builder, yaboot-xcat, conserver-xcat -- so
# most of it is not installed on a given node. dnf answers "No match for argument" and fails
# the whole call when nothing in the list matches, and apt answers "Unable to locate package".
# So go-xcat asks the package database first, and only the installed names reach it.
#
# go-xcat is sourced. rpm and dpkg-query are shell functions here, so the answer does not
# depend on what the build host has installed. Only "bash" is installed.

load 'helpers/go_xcat'

setup()
{
    go_xcat_require_source
    # shellcheck disable=SC1090
    source "$GO_XCAT_SOURCE"
    # Replaces the go-xcat function, so the test removes nothing from the host.
    remove_package() { printf 'remove %s\n' "$@"; }
}

# The real package tools must not answer. A shell function still resolves with an empty PATH.
without_path()
{
    local PATH=""
    "$@"
}

use_rpm()
{
    rpm() { [ "$1 $2" = "-q --quiet" ] && [ "$3" = bash ]; }
}

use_deb()
{
    dpkg-query() { [ "$3" = bash ] && printf 'install ok installed'; }
}

@test "rpm: only the installed packages are reported" {
    use_rpm
    run without_path installed_packages xcat-test-absent-1 bash xcat-test-absent-2
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "deb: only the installed packages are reported" {
    use_deb
    run without_path installed_packages xcat-test-absent-1 bash xcat-test-absent-2
    [ "$status" -eq 0 ]
    [ "$output" = "bash" ]
}

@test "rpm: a list with nothing installed reports nothing" {
    use_rpm
    run without_path installed_packages xcat-test-absent-1 xcat-test-absent-2
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "deb: a list with nothing installed reports nothing" {
    use_deb
    run without_path installed_packages xcat-test-absent-1 xcat-test-absent-2
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "only the installed packages reach the package manager" {
    use_rpm
    GO_XCAT_UNINSTALL_LIST=(xCAT-genesis-builder xcat-test-absent-1 bash)
    run without_path uninstall_xcat -y
    [ "$status" -eq 0 ]
    [ "$output" = "remove -y
remove bash" ]
}

@test "a node with none of them installed hands the package manager nothing, and succeeds" {
    use_rpm
    GO_XCAT_UNINSTALL_LIST=(xCAT-genesis-builder xcat-test-absent-1)
    run without_path uninstall_xcat -y
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
