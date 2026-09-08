#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    SCRIPT_LIB="$(repo_path 'xCAT-server/share/xcat/install/scripts/scriptlib')"
    XCATLIB="$(repo_path 'xCAT/postscripts/xcatlib.sh')"
    [ -r "$SCRIPT_LIB" ] || skip "$SCRIPT_LIB is required"
    [ -r "$XCATLIB" ] || skip "$XCATLIB is required"
    export SCRIPT_LIB XCATLIB
}

capture_install_scriptlib_wget()
{
    local wget_log="$1"

    wget()
    {
        printf '%s\n' "$*" >"$wget_log"
        return 0
    }

    source "$SCRIPT_LIB"
    xcat_download_postscripts "192.0.2.10:80" "/install" "/xcatpost" "$wget_log"
}

capture_xcatlib_wget()
{
    local wget_log="$1"

    xcatpost="${BATS_TEST_TMPDIR}/xcatpost"
    INSTALLDIR=/install

    echolog() { :; }
    sleep() { :; }
    grep()
    {
        [ "${*: -1}" = "/tmp/wget.log" ] && return 1
        command grep "$@"
    }
    wget()
    {
        printf '%s\n' "$*" >"$wget_log"
        return 0
    }

    source "$XCATLIB"
    download_postscripts 192.0.2.10:80
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

@test "postscript xcatlib recursive download rejects dispatcher scripts" {
    local wget_log="${BATS_TEST_TMPDIR}/xcatdsklspost-wget.log"

    run capture_xcatlib_wget "$wget_log"
    [ "$status" -eq 0 ]
    assert_download_policy "$(read_file_or_empty "$wget_log")"
}
