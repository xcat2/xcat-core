#!/usr/bin/env bats
#
# builddeb-genesis-base builds the Genesis base deb natively on Ubuntu. It writes the target
# architecture into debian/control, which is held in the amd64 form in the tree. 2.19 renames
# the ppc64 debs to ppc64el, so the ppc control must also name the deb it supersedes: without
# the relation dpkg keeps xcat-genesis-base-ppc64 installed beside the new package, and that
# old package owns the same files under /opt/xcat/share/xcat/netboot/genesis.
#
# The script needs dracut and root, so rewrite_control() is lifted out of it and run alone
# against the control file the tree ships.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(repo_path 'xCAT-genesis-builder/builddeb-genesis-base')"
    CONTROL="$(repo_path 'xCAT-genesis-builder/debian/control')"
    [ -r "$SCRIPT" ] || skip "$SCRIPT is required"
    [ -r "$CONTROL" ] || skip "$CONTROL is required"
    export SCRIPT CONTROL
}

# Run the lifted rewrite_control() over a copy of the control file in the tree, and print it.
rewrite()
{
    local arch="$1" function copy="${BATS_TEST_TMPDIR}/control.$1"

    function="$(extract_shell_function "$SCRIPT" rewrite_control)" ||
        { echo 'rewrite_control() no longer matches in builddeb-genesis-base' >&2; return 99; }
    cp "$CONTROL" "$copy"
    (
        set -eu
        eval "$function"
        rewrite_control "$copy" "$arch"
    ) || return 1
    cat "$copy"
}

@test "the amd64 control names the package and the genesis deb it took over from" {
    run rewrite amd64
    [ "$status" -eq 0 ]

    [[ "$output" =~ (^|$'\n')"Package: xcat-genesis-base-amd64"($'\n'|$) ]]
    [[ "$output" =~ (^|$'\n')"Replaces: xcat-genesis-amd64"($'\n'|$) ]]
    [[ "$output" =~ (^|$'\n')"Breaks: xcat-genesis-amd64, " ]]
    [[ "$output" =~ "xcat-genesis-scripts-amd64 (<< 2.13.10)" ]]
}

@test "the ppc64el control also takes over from the ppc64 deb the rename leaves behind" {
    run rewrite ppc64el
    [ "$status" -eq 0 ]

    [[ "$output" =~ (^|$'\n')"Package: xcat-genesis-base-ppc64el"($'\n'|$) ]]
    [[ "$output" =~ (^|$'\n')"Replaces: xcat-genesis-ppc64, xcat-genesis-base-ppc64"($'\n'|$) ]]
    [[ "$output" =~ (^|$'\n')"Breaks: xcat-genesis-ppc64, xcat-genesis-base-ppc64, " ]]
    [[ "$output" =~ "xcat-genesis-scripts-ppc64el (<< 2.13.10)" ]]
}
