#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    DSKLSPOST="$(repo_path 'xCAT/postscripts/xcatdsklspost')"
    [ -r "$DSKLSPOST" ] || skip "$DSKLSPOST is required"
    XCATPOST="${BATS_TEST_TMPDIR}/xcatpost"
    MYPS="${BATS_TEST_TMPDIR}/mypostscript"
    MSGLOG="${BATS_TEST_TMPDIR}/msgutil.log"
    export DSKLSPOST XCATPOST MYPS MSGLOG
}

# A scratch /xcatpost with what an updatenode run downloads into it.
make_xcatpost()
{
    mkdir -p "$XCATPOST/_xcat"
    printf 'updateflag\n' >"$XCATPOST/updateflag.awk"
    printf 'setroute\n' >"$XCATPOST/setroute"
    printf 'xcatlib\n' >"$XCATPOST/xcatlib.sh"
    printf 'credentials\n' >"$XCATPOST/_xcat/postscript.cfg"
}

# A scratch mypostscript that carries the site values and the run result.
# $1 is the value of return_value, the rest are the site table lines.
make_mypostscript()
{
    local result=$1
    shift
    {
        printf '%s\n' '#!/bin/bash'
        printf 'msgutil_r() { printf "%%s\\n" "$3" >>"%s"; }\n' "$MSGLOG"
        printf 'MASTER_IP=192.0.2.1\n'
        printf 'NODE=node1\n'
        printf 'log_label=xcat.updatenode\n'
        printf 'return_value=%s\n' "$result"
        printf '%s\n' "$@"
    } >"$MYPS"
}

append_cleanup()
{
    (
        XCATDSKLSPOST_SOURCE_ONLY=1
        export XCATDSKLSPOST_SOURCE_ONLY
        # shellcheck disable=SC1090
        . "$DSKLSPOST"
        type -t append_xcatpost_cleanup >/dev/null \
            || { echo "xcatdsklspost defines no append_xcatpost_cleanup" >&2; exit 99; }
        append_xcatpost_cleanup "$MYPS" "$XCATPOST"
    )
}

@test "an updatenode run that succeeds removes the postscripts when site.cleanupdiskfullxcatpost is set" {
    make_xcatpost
    make_mypostscript 0 "CLEANUPXCATPOST='no'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ ! -e "$XCATPOST/setroute" ]
    [ ! -e "$XCATPOST/xcatlib.sh" ]
    [ ! -e "$XCATPOST/_xcat" ]
}

@test "the cleanup keeps updateflag.awk so the node can still report its status" {
    make_xcatpost
    make_mypostscript 0 "CLEANUPXCATPOST='no'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -f "$XCATPOST/updateflag.awk" ]
    [ -d "$XCATPOST" ]
    grep -q 'cleanup of .* completed' "$MSGLOG"
}

@test "an updatenode run that fails keeps the postscripts for diagnosis" {
    make_xcatpost
    make_mypostscript 1 "CLEANUPXCATPOST='no'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -f "$XCATPOST/setroute" ]
    [ -f "$XCATPOST/_xcat/postscript.cfg" ]
    refute_grep -q 'cleanup of .* completed' "$MSGLOG"
}

@test "site.cleanupdiskfullxcatpost accepts the other true values of the site table" {
    make_xcatpost
    make_mypostscript 0 "CLEANUPDISKFULLXCATPOST='1'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ ! -e "$XCATPOST/setroute" ]
}

# cleanupdiskfullxcatpost names the node type it applies to. updatenode calls this script for a
# diskless or statelite node as well, and the site value is one row that reaches all of them, so
# without a guard a diskless node loses its postscripts to a setting that does not name it.
@test "a netboot node keeps its postscripts when site.cleanupdiskfullxcatpost is set" {
    make_xcatpost
    make_mypostscript 0 "NODESETSTATE='netboot'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -f "$XCATPOST/setroute" ]
    [ -f "$XCATPOST/_xcat/postscript.cfg" ]
    # Nothing was appended, so the run cannot report a cleanup it did not do.
    refute_grep -q 'cleanup of .* completed' "$MSGLOG"
}

@test "a statelite node keeps its postscripts when site.cleanupdiskfullxcatpost is set" {
    make_xcatpost
    make_mypostscript 0 "NODESETSTATE='statelite'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -f "$XCATPOST/setroute" ]
}

@test "a diskful node is still cleaned when site.cleanupdiskfullxcatpost is set" {
    make_xcatpost
    make_mypostscript 0 "NODESETSTATE='install'" "CLEANUPDISKFULLXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ ! -e "$XCATPOST/setroute" ]
    [ -f "$XCATPOST/updateflag.awk" ]
}

# site.cleanupxcatpost names no node type, so it keeps applying to every one. A guard added to the
# wrong branch would show up here.
@test "site.cleanupxcatpost still applies to a netboot node" {
    make_xcatpost
    make_mypostscript 0 "NODESETSTATE='netboot'" "CLEANUPXCATPOST='yes'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$XCATPOST")" ]
}

@test "site.cleanupxcatpost removes every file including updateflag.awk" {
    make_xcatpost
    make_mypostscript 0 "CLEANUPXCATPOST='yes'" "CLEANUPDISKFULLXCATPOST='no'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -z "$(ls -A "$XCATPOST")" ]
}

@test "neither setting leaves the downloaded postscripts in place" {
    make_xcatpost
    make_mypostscript 0 "CLEANUPXCATPOST='no'" "CLEANUPDISKFULLXCATPOST='no'"
    append_cleanup

    run bash "$MYPS"
    [ "$status" -eq 0 ]
    [ -f "$XCATPOST/setroute" ]
    [ -f "$XCATPOST/updateflag.awk" ]
    refute_grep -q -E 'rm -rf|-delete' "$MYPS"
}
