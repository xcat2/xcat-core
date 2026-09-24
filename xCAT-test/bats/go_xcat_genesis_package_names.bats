#!/usr/bin/env bats
#
# go-xcat installs and uninstalls a fixed list of package names, and it keeps one list per
# packaging format. The Genesis packages are named after the architecture, and the two formats
# spell it differently: the rpm is xCAT-genesis-scripts-ppc64, the deb is
# xcat-genesis-scripts-ppc64el.
#
# The lists are built by go-xcat itself here, not read as text: the deb list exists only when
# "type dpkg" succeeds, so a shell function decides which branch each run takes.

load 'helpers/go_xcat'
load 'helpers/shell_source'

setup()
{
    go_xcat_require_source
    SCRIPTS_DEBIAN="$(repo_path 'xCAT-genesis-scripts/debian')"
    SPEC="$(repo_path 'xCAT-genesis-base/xCAT-genesis-base.spec')"
    [ -d "$SCRIPTS_DEBIAN" ] || skip "$SCRIPTS_DEBIAN is required"
    [ -r "$SPEC" ] || skip "$SPEC is required"
    export SCRIPTS_DEBIAN SPEC
}

# Run the array definitions of go-xcat and print the two lists it built, one per line.
package_lists()
{
    local want_dpkg="$1" list_body
    list_body="$(awk '
        /^GO_XCAT_INSTALL_LIST=\(/ { copy = 1 }
        /^PATH=/ { exit }
        copy { print }
    ' "$GO_XCAT_SOURCE")"
    [ -n "$list_body" ] || { echo 'go-xcat package arrays not found' >&2; return 3; }
    (
        if [ "$want_dpkg" = 1 ]; then
            dpkg() { :; }
        fi
        # A real dpkg on the build host would select the deb branch on every run.
        PATH=""
        eval "$list_body"
        printf 'install %s\n' "${GO_XCAT_INSTALL_LIST[*]}"
        printf 'uninstall %s\n' "${GO_XCAT_UNINSTALL_LIST[*]}"
    )
}

package_list()
{
    package_lists "$1" | sed -n "s/^$2 //p"
}

# The package names of a list, sorted, that start with a prefix.
named()
{
    local prefix="$1" word
    for word in $(cat); do
        case "$word" in
        "$prefix"*) printf '%s\n' "$word" ;;
        esac
    done | sort
}

# The deb names come from the packaging: one control file per Debian architecture names the
# genesis-scripts package, and its Depends names the genesis-base package that carries the
# Genesis tree for that same architecture.
control_scripts_packages()
{
    grep -h '^Package:' "$SCRIPTS_DEBIAN"/control-* | awk '{ print $2 }' | sort
}

control_base_packages()
{
    grep -h '^Depends:' "$SCRIPTS_DEBIAN"/control-* |
        grep -o 'xcat-genesis-base-[a-z0-9]\+' | sort
}

# The Genesis target architectures of the spec, which are not Debian architecture names.
spec_target_arches()
{
    awk '$1 == "%define" && $2 == "tarch" { print $3 }' "$SPEC" | sort -u
}

# The names of a list that carry an architecture the spec does not define.
unknown_target_arches()
{
    local prefix="$1" name arch
    while read -r name; do
        arch="${name#"$prefix"}"
        spec_target_arches | grep -qx "$arch" || printf '%s\n' "$name"
    done
}

@test "the package lists of go-xcat can be built for both packaging formats" {
    [ -n "$(control_scripts_packages)" ]
    [ -n "$(spec_target_arches)" ]

    run package_list 1 install
    [ "$status" -eq 0 ]
    [[ " $output " == *' xcat-client '* ]]

    run package_list 0 install
    [ "$status" -eq 0 ]
    [[ " $output " == *' xCAT-client '* ]]
}

@test "the deb install list names the genesis packages the Debian control files declare" {
    list="$(package_list 1 install)"
    [ "$(printf '%s' "$list" | named 'xcat-genesis-scripts-')" = "$(control_scripts_packages)" ]
    [ "$(printf '%s' "$list" | named 'xcat-genesis-base-')" = "$(control_base_packages)" ]
}

@test "the deb uninstall list names the genesis packages the Debian control files declare" {
    list="$(package_list 1 uninstall)"
    [ "$(printf '%s' "$list" | named 'xcat-genesis-scripts-')" = "$(control_scripts_packages)" ]
    [ "$(printf '%s' "$list" | named 'xcat-genesis-base-')" = "$(control_base_packages)" ]
}

@test "the rpm install list names only Genesis target architectures" {
    list="$(package_list 0 install)"
    for prefix in xCAT-genesis-scripts- xCAT-genesis-base-; do
        [ -z "$(printf '%s' "$list" | named "$prefix" | unknown_target_arches "$prefix")" ]
    done
}

@test "the rpm uninstall list names only Genesis target architectures" {
    list="$(package_list 0 uninstall)"
    for prefix in xCAT-genesis-scripts- xCAT-genesis-base-; do
        [ -z "$(printf '%s' "$list" | named "$prefix" | unknown_target_arches "$prefix")" ]
    done
}
