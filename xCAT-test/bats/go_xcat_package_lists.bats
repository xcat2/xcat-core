#!/usr/bin/env bats
#
# go-xcat installs one package list and removes another, with the deb names when "type dpkg"
# succeeds. On riscv64 it drops the legacy Genesis, which has no riscv64 build, and asks for the
# OpenEmbedded Genesis instead. The x86 boot loaders stay: a riscv64 management node serves them
# to the x86 nodes of a mixed cluster.
#
# Each test sources go-xcat in a subshell and reads the lists the installer would use.

load 'helpers/go_xcat'

LEGACY_GENESIS='-genesis-(scripts|base)-'

setup()
{
    go_xcat_require_source
}

# Print one list of go-xcat, one package per line.
#
#	$1	The package format: rpm or deb.
#	$2	install, uninstall, or riscv64 for the install list of a riscv64 management node.
go_xcat_list()
{
    local format="$1" list="$2"
    (
        if [ "$format" = "deb" ]; then
            dpkg() { :; }
        fi
        # A real dpkg on the build host would select the deb names on every run. go-xcat sets PATH
        # again, and riscv64_install_list looks for dpkg too.
        PATH=""
        source "$GO_XCAT_SOURCE" || exit 70
        PATH=""
        case "$list" in
        install) printf '%s\n' "${GO_XCAT_INSTALL_LIST[@]}" ;;
        uninstall) printf '%s\n' "${GO_XCAT_UNINSTALL_LIST[@]}" ;;
        riscv64) riscv64_install_list "${GO_XCAT_INSTALL_LIST[@]}" ;;
        *) exit 64 ;;
        esac
    )
}

openembedded_genesis()
{
    case "$1" in
    rpm) echo 'xCAT-genesis-openembedded-riscv64' ;;
    deb) echo 'xcat-genesis-openembedded-riscv64' ;;
    esac
}

# Print the lines of the first list that the second list does not have.
missing_from()
{
    local list="$1" other="$2" package
    while IFS= read -r package; do
        grep -Fqx -- "$package" <<<"$other" || printf '%s\n' "$package"
    done <<<"$list"
}

@test "go-xcat loads its package lists without running the installer" {
    for format in rpm deb; do
        for list in install uninstall riscv64; do
            run go_xcat_list "$format" "$list"
            [ "$status" -eq 0 ]
            [ -n "$output" ]
        done
    done
}

@test "the riscv64 install list has no legacy Genesis and asks for the OpenEmbedded Genesis" {
    for format in rpm deb; do
        riscv64="$(go_xcat_list "$format" riscv64)"
        [ -z "$(grep -E -- "$LEGACY_GENESIS" <<<"$riscv64")" ]
        grep -Fqx -- "$(openembedded_genesis "$format")" <<<"$riscv64"
    done
}

@test "the riscv64 install list keeps every other package, the x86 boot loaders included" {
    for format in rpm deb; do
        install="$(go_xcat_list "$format" install)"
        riscv64="$(go_xcat_list "$format" riscv64)"
        [ -n "$(grep -E -- "$LEGACY_GENESIS" <<<"$install")" ]

        run missing_from "$(grep -v -E -- "$LEGACY_GENESIS" <<<"$install")" "$riscv64"
        [ -z "$output" ] || { echo "$format: the riscv64 list drops: $output"; false; }

        run missing_from "$riscv64" "$install"
        [ "$output" = "$(openembedded_genesis "$format")" ]
    done
}

@test "the uninstall list removes every package go-xcat installs on any architecture" {
    for format in rpm deb; do
        uninstall="$(go_xcat_list "$format" uninstall)"
        for list in install riscv64; do
            run missing_from "$(go_xcat_list "$format" "$list")" "$uninstall"
            [ -z "$output" ] || { echo "$format: uninstall misses $list packages: $output"; false; }
        done
    done
}

@test "every install list asks for ipxe-xcat and xnba-undi" {
    for format in rpm deb; do
        for list in install riscv64; do
            packages="$(go_xcat_list "$format" "$list")"
            for package in ipxe-xcat xnba-undi; do
                grep -Fqx "$package" <<<"$packages" || { echo "$format $list: no $package"; false; }
            done
        done
    done
}
