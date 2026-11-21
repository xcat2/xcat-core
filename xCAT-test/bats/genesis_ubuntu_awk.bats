#!/usr/bin/env bats
#
# The awk the Ubuntu Genesis image carries.
#
# allowcred.awk, minixcatd.awk and udpcat.awk open a TCP stream with the gawk |& coprocess
# and the /inet/ special file. mawk rejects both at parse time, and mawk is the awk
# alternative on a Debian or Ubuntu build root, so the module cannot stage the host's
# /usr/bin/awk.

load 'helpers/shell_source'

setup()
{
    MODULE="$(repo_path 'xCAT-genesis-base/dracut_105/ubuntu/module-setup.sh')"
    [ -r "$MODULE" ] || skip "$MODULE is required"
    export MODULE
}

# Run install() from the dracut module with the dracut helpers replaced by stubs. Sets
# INSTALLED to one installed name per line, and INITDIR to the staged image root.
run_install()
{
    local dir="${BATS_TEST_TMPDIR}/module"

    rm -rf "$dir"
    mkdir -p "$dir/initdir/usr/bin" "$dir/initdir/bin"

    # No "set -u": _dracut_install_opt() in the module reads $2 unset, which real dracut
    # allows.
    cat >"$dir/drive.sh" <<'SH'
initdir="$1"
record="$2"
moddir=/dev/null
kernel=
dracut_install() { for name in "$@"; do printf '%s\n' "$name" >>"$record"; done; }
instmods()  { :; }
inst()      { :; }
inst_script() { :; }
inst_dir()  { :; }
inst_hook() { :; }
inst_symlink() { :; }
. "$MODULE"
install >/dev/null 2>&1
SH

    /bin/bash "$dir/drive.sh" "$dir/initdir" "$dir/installed" || true
    INSTALLED="$(read_file_or_empty "$dir/installed")"
    INITDIR="$dir/initdir"
}

@test "the module installs gawk by name" {
    run_install
    printf '%s\n' "$INSTALLED" | grep -qx 'gawk'
}

@test "the module does not stage the build host's awk alternative" {
    # On Ubuntu /usr/bin/awk resolves to mawk, so staging it ships an awk that cannot parse
    # the Genesis awk programs.
    run_install
    refute_grep -qx '/usr/bin/awk' <(printf '%s\n' "$INSTALLED")
    refute_grep -qx 'awk' <(printf '%s\n' "$INSTALLED")
}

@test "awk in the image points at gawk" {
    # The awk programs start with #!/usr/bin/awk -f, so the name awk has to be gawk.
    run_install
    [ -L "$INITDIR/usr/bin/awk" ]
    [ "$(readlink "$INITDIR/usr/bin/awk")" = 'gawk' ]
}
