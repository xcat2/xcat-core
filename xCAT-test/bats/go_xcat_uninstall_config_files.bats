#!/usr/bin/env bats
#
# `apt-get remove` leaves a package in the "deinstall ok config-files" state (dpkg `rc`).
# `go-xcat uninstall` removes, so it skips those. `go-xcat uninstall --completely` purges,
# so it must include them, or a remove followed by a complete uninstall leaves the
# configuration files behind.
#
# go-xcat is sourced. dpkg-query and the package, kill and trash steps are shell functions
# here, and PATH is empty, so no test reads or changes the host package database or files.

load 'helpers/go_xcat'

setup()
{
    go_xcat_require_source
    # shellcheck disable=SC1090
    source "$GO_XCAT_SOURCE"
    remove_package() { printf 'remove %s\n' "$@"; }
    purge_package() { printf 'purge %s\n' "$@"; }
    kill_xcat() { :; }
    trash_xcat() { :; }
    # The state dpkg reports after `apt-get remove xcat-test-removed`.
    dpkg-query()
    {
        case "$3" in
        xcat-test-installed) printf 'install ok installed' ;;
        xcat-test-removed) printf 'deinstall ok config-files' ;;
        *) return 1 ;;
        esac
    }
    GO_XCAT_UNINSTALL_LIST=(xcat-test-absent xcat-test-installed xcat-test-removed)
}

without_path()
{
    local PATH=""
    "$@"
}

@test "deb: complete uninstall purges packages that only have configuration files left" {
    run without_path uninstall_xcat_completely
    [ "$status" -eq 0 ]
    [ "$output" = "purge -y
purge xcat-test-installed
purge xcat-test-removed" ]
}

@test "deb: complete uninstall after a remove purges the removed package" {
    GO_XCAT_UNINSTALL_LIST=(xcat-test-absent xcat-test-removed)
    run without_path uninstall_xcat_completely
    [ "$status" -eq 0 ]
    [ "$output" = "purge -y
purge xcat-test-removed" ]
}

@test "deb: ordinary uninstall removes only the installed packages" {
    run without_path uninstall_xcat -y
    [ "$status" -eq 0 ]
    [ "$output" = "remove -y
remove xcat-test-installed" ]
}

@test "deb: a package with only configuration files left is not reported as installed" {
    run without_path installed_packages xcat-test-removed xcat-test-installed
    [ "$status" -eq 0 ]
    [ "$output" = "xcat-test-installed" ]
}
