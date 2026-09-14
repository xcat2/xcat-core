#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    OTHERPKGS="$(repo_path 'xCAT/postscripts/otherpkgs')"
    [ -r "$OTHERPKGS" ] || skip "$OTHERPKGS is required"
    LOGGER_LOG="${BATS_TEST_TMPDIR}/logger.log"
    CMD_LOG="${BATS_TEST_TMPDIR}/cmd.log"
    : >"$LOGGER_LOG"
    : >"$CMD_LOG"
    export OTHERPKGS LOGGER_LOG CMD_LOG
}

# logger writes one line per message it sends. A message that carries newlines stays on one
# line, with the newlines shown as "\n", so the line count is the message count.
shadow_logger()
{
    logger()
    {
        local msg=""
        while [ $# -gt 0 ]; do
            case "$1" in
            -p | -t) shift 2 ;;
            *)
                msg="$*"
                break
                ;;
            esac
        done
        if [ -n "$msg" ]; then
            printf '%s\n' "${msg//$'\n'/\\n}" >>"$LOGGER_LOG"
        else
            local line
            while IFS= read -r line; do
                printf '%s\n' "$line" >>"$LOGGER_LOG"
            done
        fi
    }
}

logger_call()
{
    sed -n "${1}p" "$LOGGER_LOG"
}

logger_calls()
{
    wc -l <"$LOGGER_LOG" | tr -d ' '
}

cmd_call()
{
    sed -n "${1}p" "$CMD_LOG"
}

# A package manager that answers with PKG_STATUS and prints a three line transaction.
shadow_pkg_manager()
{
    fake_pkg()
    {
        printf '%s\n' "$*" >>"$CMD_LOG"
        printf -- '--> Running transaction check\n'
        printf 'Installed: foo-1.0\n'
        printf 'Error: nothing provides bar\n'
        return "${PKG_STATUS:-0}"
    }
    zypper() { fake_pkg "$@"; }
    apt-get() { fake_pkg "$@"; }
    xcat_apt_get() { fake_pkg "$@"; }
    apt_get_update_if_repos_changed() { :; }
}

# Answers with the shell if-block that starts at the first line after the anchor.
otherpkgs_block()
{
    local tail="${BATS_TEST_TMPDIR}/tail-$$"
    awk -v anchor="$1" 'index($0, anchor) { copy = 1 } copy { print }' "$OTHERPKGS" >"$tail"
    extract_shell_if_block "$tail" "$2"
}

run_upgrade_block()
{
    local block
    block="$(otherpkgs_block '#now update the existing rpms' 'if [ $hasyum -eq 1 ]; then')" || return 99
    local hasyum=0 haszypper=0 hasapt=0
    eval "$1=1"
    local envlist="" yumcmd=fake_pkg VERBOSE= log_label=otherpkgs RETURNVAL=0 REPOFILE=/dev/null result=""
    shadow_logger
    shadow_pkg_manager
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

run_repo_preremove_block()
{
    local block
    block="$(otherpkgs_block '#Now we have parsed the input' 'if [ "$repo_pkgs_preremove" != "" ]; then')" || return 99
    local hasyum=0 haszypper=0 hasapt=0
    eval "$1=1"
    local envlist="" yumcmd=fake_pkg VERBOSE= log_label=otherpkgs RETURNVAL=0 REPOFILE=/dev/null result=""
    local repo_pkgs_preremove="oldfoo"
    shadow_logger
    shadow_pkg_manager
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

run_plain_preremove_block()
{
    local block
    block="$(otherpkgs_block '#Now we have parsed the input' 'if [ "$plain_pkgs_preremove" != "" ]; then')" || return 99
    local envlist="" VERBOSE= log_label=otherpkgs RETURNVAL=0 result=""
    local sremovecommand=fake_pkg plain_pkgs_preremove="oldfoo"
    shadow_logger
    shadow_pkg_manager
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

@test "otherpkgs sends the package manager transaction to syslog one line per message" {
    run run_upgrade_block hasyum
    [ "$status" -eq 0 ]
    [ "$(logger_calls)" -eq 3 ]
    [ "$(logger_call 1)" = "--> Running transaction check" ]
    [ "$(logger_call 2)" = "Installed: foo-1.0" ]
    [ "$(logger_call 3)" = "Error: nothing provides bar" ]
}

@test "the zypper and apt upgrade paths also send one message per output line" {
    run run_upgrade_block haszypper
    [ "$status" -eq 0 ]
    [ "$(logger_calls)" -eq 3 ]

    : >"$LOGGER_LOG"
    run run_upgrade_block hasapt
    [ "$status" -eq 0 ]
    [ "$(logger_calls)" -eq 3 ]
}

@test "the remove paths also send one message per output line" {
    local manager
    for manager in hasyum haszypper hasapt; do
        : >"$LOGGER_LOG"
        run run_repo_preremove_block "$manager"
        [ "$status" -eq 0 ]
        [ "$(logger_calls)" -eq 3 ]
    done

    : >"$LOGGER_LOG"
    run run_plain_preremove_block
    [ "$status" -eq 0 ]
    [ "$(logger_calls)" -eq 3 ]
}

run_install_block()
{
    local block
    block="$(otherpkgs_block '#installation using yum/dnf or zypper' 'if [ "$repo_pkgs" != "" ]; then')" || return 99
    local hasyum=0 haszypper=0 hasapt=0
    eval "$1=1"
    local envlist="" yumcmd=fake_pkg VERBOSE= log_label=otherpkgs RETURNVAL=0 REPOFILE=/dev/null result=""
    local repo_pkgs="foo bar"
    shadow_logger
    shadow_pkg_manager
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

run_repo_postremove_block()
{
    local block
    block="$(otherpkgs_block '#remove more rpms if specified with' 'if [ "$repo_pkgs_postremove" != "" ]; then')" || return 99
    local hasyum=0 haszypper=0 hasapt=0
    eval "$1=1"
    local envlist="" yumcmd=fake_pkg VERBOSE= log_label=otherpkgs RETURNVAL=0 REPOFILE=/dev/null result=""
    local repo_pkgs_postremove="oldfoo"
    shadow_logger
    shadow_pkg_manager
    eval "$block"
    printf 'RETURNVAL=%s\n' "$RETURNVAL"
}

@test "a failed package install is not logged as installed" {
    local manager
    for manager in hasyum haszypper hasapt; do
        : >"$LOGGER_LOG"
        PKG_STATUS=1 run run_install_block "$manager"
        [ "$status" -eq 0 ]
        [[ "$output" == *'RETURNVAL=1'* ]]
        refute_grep -q 'foo bar installed\.' "$LOGGER_LOG"
        grep -q 'failed\.' "$LOGGER_LOG"
    done
}

@test "a successful package install is logged as installed" {
    local manager
    for manager in hasyum haszypper hasapt; do
        : >"$LOGGER_LOG"
        run run_install_block "$manager"
        [ "$status" -eq 0 ]
        [[ "$output" == *'RETURNVAL=0'* ]]
        grep -q 'foo bar installed\.' "$LOGGER_LOG"
        refute_grep -q 'failed\.' "$LOGGER_LOG"
    done
}

@test "a failed package removal is not logged as removed" {
    local manager
    for manager in hasyum haszypper hasapt; do
        : >"$LOGGER_LOG"
        PKG_STATUS=1 run run_repo_postremove_block "$manager"
        [ "$status" -eq 0 ]
        [[ "$output" == *'RETURNVAL=1'* ]]
        refute_grep -q 'oldfoo removed\.' "$LOGGER_LOG"
    done

    : >"$LOGGER_LOG"
    run run_repo_postremove_block hasyum
    [ "$status" -eq 0 ]
    grep -q 'oldfoo removed\.' "$LOGGER_LOG"
}

@test "the url repository guard is false when OTHERPKGDIR has no http entry" {
    local guard cond
    guard="$(extract_first_matching_line "$OTHERPKGS" 'OTHERPKGDIR_INTERNET" *[]] *; *then')" || return 99
    cond="${guard#*if }"
    cond="${cond%%;then*}"

    OTHERPKGDIR_INTERNET=""
    run eval "$cond"
    [ "$status" -ne 0 ]

    OTHERPKGDIR_INTERNET="http://192.0.2.1/repo,"
    run eval "$cond"
    [ "$status" -eq 0 ]
}

# Runs the OTHERPKGDIR split and then the url repository block, and leaves the repository
# files the url block wrote under BATS_TEST_TMPDIR.
run_url_repo_block()
{
    local split url_block
    split="$(extract_shell_if_block "$OTHERPKGS" 'if [ -n "$OTHERPKGDIR" ]; then')" || return 99
    url_block="$(otherpkgs_block '#add repo for url repos in otherpkgdir' 'OTHERPKGDIR_INTERNET')" || return 99
    local OTHERPKGDIR="$1" OTHERPKGDIR_INTERNET="" OTHERPKGDIR_LOCAL=""
    local hasyum="${2:-1}" haszypper=0 hasapt="${3:-0}"
    local repo_base="$BATS_TEST_TMPDIR" urlrepoindex=0
    eval "$split"
    eval "$url_block"
    printf 'urlrepoindex=%s\n' "$urlrepoindex"
}

@test "the generated yum baseurl carries no trailing space" {
    run run_url_repo_block 'http://192.0.2.1/repo-a,/install/post/otherpkgs,http://192.0.2.1/repo-b'
    [ "$status" -eq 0 ]
    [[ "$output" == *'urlrepoindex=2'* ]]
    [ "$(grep '^baseurl=' "${BATS_TEST_TMPDIR}/xCAT-otherpkgs0.repo")" = "baseurl=http://192.0.2.1/repo-a" ]
    [ "$(grep '^baseurl=' "${BATS_TEST_TMPDIR}/xCAT-otherpkgs1.repo")" = "baseurl=http://192.0.2.1/repo-b" ]
}

@test "the generated apt source carries no trailing space" {
    run run_url_repo_block 'http://192.0.2.1/repo-a' 0 1
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/xCAT-otherpkgs0.list")" = "deb http://192.0.2.1/repo-a" ]
}

# Drives the lines that name the local otherpkgs repository for zypper: the alias written into
# the repository file, and the alias the refresh and the delete use.
run_zypper_local_repo()
{
    local urlrepoindex="$1" index="$2"
    local repo_base="$BATS_TEST_TMPDIR" mounted=1 whole_path=/install/post/otherpkgs/sles15/x86_64
    local OSVER=sles15 VERBOSE= localrepoindex REPOFILE rc=1 result="" path=/pkgdir
    zypper()
    {
        printf '%s\n' "$*" >>"$CMD_LOG"
        case "$1" in
        ar) sed -n '1s/^\[\(.*\)\]$/added=\1/p' "$3" >>"$CMD_LOG" ;;
        esac
        return "${ZYPPER_STATUS:-0}"
    }
    array_set_element() { :; }
    # The extraction is kept apart from the eval: a failing zypper must not read as a failed
    # extraction.
    local pattern line
    for pattern in \
        'localrepoindex=' \
        'REPOFILE="[$]repo_base/xCAT-otherpkgs[$]localrepoindex.repo"' \
        'echo "[[]xcat-otherpkgs[$]localrepoindex[]]"' \
        'result=`zypper ar -c [$]REPOFILE`' \
        'zypper --non-interactive refresh xcat-otherpkgs' \
        'result=`zypper sd xcat-otherpkgs'; do
        line="$(extract_first_matching_line "$OTHERPKGS" "$pattern")" || return 99
        eval "$line"
    done
    return 0
}

@test "zypper refreshes the otherpkgs repository it added" {
    run run_zypper_local_repo 2 0
    [ "$status" -eq 0 ]
    [ "$(cmd_call 2)" = "added=xcat-otherpkgs2" ]
    [ "$(cmd_call 3)" = "--non-interactive refresh xcat-otherpkgs2" ]
}

@test "zypper deletes the otherpkgs repository it added when the refresh fails" {
    ZYPPER_STATUS=1 run run_zypper_local_repo 2 0
    [ "$status" -eq 0 ]
    [ "$(cmd_call 2)" = "added=xcat-otherpkgs2" ]
    [ "$(cmd_call 4)" = "sd xcat-otherpkgs2" ]
}

run_sdk_block()
{
    local block
    block="$(otherpkgs_block '#adds SDK repository' 'if [ "$SDKDIR" != "" ]; then')" || return 99
    local SDKDIR=/install/sles15/x86_64/sdk1 OSVER=sles15 mounted=1 VERBOSE= log_label=otherpkgs result=""
    local NFSSERVER=192.0.2.1 HTTPPORT=80
    eval "$(extract_shell_function "$OTHERPKGS" pmatch)" || return 99
    shadow_logger
    zypper()
    {
        printf 'zypper failed\n'
        return 1
    }
    eval "$block"
    return 0
}

@test "a failed SDK repository add is logged with the repository name" {
    run run_sdk_block
    [ "$status" -eq 0 ]
    grep -q 'xCAT-sles15-sdk1' "$LOGGER_LOG"
}
