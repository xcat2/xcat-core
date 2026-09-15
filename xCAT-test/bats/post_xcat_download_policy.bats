#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    SCRIPT_LIB="$(require_repo_file 'xCAT-server/share/xcat/install/scripts/scriptlib')"
    XCATDSKLSPOST="$(require_repo_file 'xCAT/postscripts/xcatdsklspost')"
    export SCRIPT_LIB XCATDSKLSPOST
}

capture_install_scriptlib_wget()
{
    local wget_log="$1"

    wget()
    {
        printf '%s\n' "$*" >"$wget_log"
        return 0
    }

    local postroot="${BATS_TEST_TMPDIR}/xcatpost"

    source "$SCRIPT_LIB"
    require_scratch_path "$postroot" || return 1
    PATH="$(sandbox_path)"
    xcat_download_postscripts "192.0.2.10:80" "/install" "$postroot" "$wget_log"
}

capture_xcatdsklspost_wget()
{
    local wget_log="$1"
    local host_init_log="${BATS_TEST_TMPDIR}/host-init.log"
    local download_log="${BATS_TEST_TMPDIR}/xcatdsklspost-wget-errors.log"

    cat() { printf 'cat %s\n' "$*" >>"$host_init_log"; return 1; }
    grep()
    {
        printf 'grep %s\n' "$*" >>"$host_init_log"
        command grep "$@"
    }
    dirname() { printf 'dirname %s\n' "$*" >>"$host_init_log"; return 1; }

    XCATDSKLSPOST_SOURCE_ONLY=1
    XCAT_WGET_LOG="$download_log"
    source "$XCATDSKLSPOST"
    [ ! -e "$host_init_log" ] || return 1
    [ "$XCAT_WGET_LOG" = "$download_log" ] || return 1
    unset -f cat grep dirname

    xcatpost="${BATS_TEST_TMPDIR}/xcatpost"
    # download_postscripts runs rm -rf "$xcatpost" before the download.
    require_scratch_path "$xcatpost" || return 1
    INSTALLDIR=/install
    echolog() { :; }
    sleep() { :; }
    wget()
    {
        printf '%s\n' "$*" >"$wget_log"
        printf '%s\n' 'mock wget stderr' >&2
        return 0
    }

    PATH="$(sandbox_path grep cut rm cat mkdir)"
    download_postscripts 192.0.2.10:80
    [ "$(read_file_or_empty "$download_log")" = "mock wget stderr" ]
}

assert_download_policy()
{
    local args="$1"

    [[ "$args" == *'--reject index.html*,post.xcat.ng,post.xcat.rhels10'* ]]
    [[ "$args" == *'--no-parent'* ]]
    [[ "$args" == *'postscripts/'* ]]
    [[ "$args" != *'<a href='* ]]
}

@test "install scriptlib recursive download rejects dispatcher scripts" {
    local wget_log="${BATS_TEST_TMPDIR}/post-xcat-wget.log"

    run capture_install_scriptlib_wget "$wget_log"
    [ "$status" -eq 0 ]
    assert_download_policy "$(read_file_or_empty "$wget_log")"
}

@test "xcatdsklspost recursive download rejects dispatcher scripts" {
    local wget_log="${BATS_TEST_TMPDIR}/xcatdsklspost-wget.log"

    run capture_xcatdsklspost_wget "$wget_log"
    [ "$status" -eq 0 ]
    assert_download_policy "$(read_file_or_empty "$wget_log")"
}
