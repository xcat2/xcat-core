#!/usr/bin/env bats
#
# go-xcat check, install and update print a table of the xCAT packages, with the installed version
# and the version that the repositories offer. On apt, the table must show the candidates that a
# translated apt reports. A terminal type that tput does not know must not add tput errors to it.

load 'helpers/go_xcat'
load 'helpers/go_xcat_apt'

setup()
{
    go_xcat_require_source
}

# Print the package table of list_xcat_packages with the apt-cache double. xcat-core offers xcat and
# xcat-server, xcat-dep offers ipmitool-xcat, and none of them is installed.
list_packages()
{
    (
        PATH=""
        source "$GO_XCAT_SOURCE" || exit 70
        get_package_list()
        {
            case "$1" in
            xcat-core) echo xcat xcat-server ;;
            xcat-dep) echo ipmitool-xcat ;;
            esac
        }
        check_package_version()
        {
            local package
            for package in "$@"; do
                echo '(not installed)'
            done
        }
        list_xcat_packages
    )
}

# Succeed when the table offers version 1.0-1 of every package.
offers_every_package()
{
    local package
    for package in xcat xcat-server ipmitool-xcat; do
        grep -Eq "^${package} +\\(not installed\\) +1\\.0-1 *\$" <<<"$1" || return 1
    done
}

@test "the package table shows the apt candidates" {
    LANG=C LC_ALL=C run list_packages
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    offers_every_package "$output" || { printf '%s\n' "$output"; return 1; }
}

@test "the package table shows the candidates that a translated apt reports" {
    LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 run list_packages
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    offers_every_package "$output" || { printf '%s\n' "$output"; return 1; }
}

@test "an unknown terminal type adds no tput error to the package table" {
    command -v tput >/dev/null || skip "tput is required"
    TERM=xcat-unknown-terminal run list_packages
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    offers_every_package "$output" || { printf '%s\n' "$output"; return 1; }
    if grep -F 'tput' <<<"$output"; then return 1; fi
}

@test "an empty TERM adds no tput error to the package table" {
    command -v tput >/dev/null || skip "tput is required"
    TERM= run list_packages
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    offers_every_package "$output" || { printf '%s\n' "$output"; return 1; }
    if grep -F 'tput' <<<"$output"; then return 1; fi
}
