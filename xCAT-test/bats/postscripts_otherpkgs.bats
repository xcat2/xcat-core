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
