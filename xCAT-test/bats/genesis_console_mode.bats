#!/usr/bin/env bats
#
# Drive xcat_console_mode() out of the Genesis dracut cmdline hook.
#
# The hook cannot be sourced: it mounts filesystems, starts udev and ends in an endless
# loop. Extract the one function and run it with the terminal multiplexer shadowed.

load 'helpers/shell_source'

setup()
{
    EL_HOOK="$(repo_path 'xCAT-genesis-base/dracut_105/el/xcat-cmdline.sh')"
    UBUNTU_HOOK="$(repo_path 'xCAT-genesis-base/dracut_105/ubuntu/xcat-cmdline.sh')"
    [ -r "$EL_HOOK" ] || skip "$EL_HOOK is required"
    [ -r "$UBUNTU_HOOK" ] || skip "$UBUNTU_HOOK is required"
    export EL_HOOK UBUNTU_HOOK
}

# Run the extracted function with the multiplexer shadowed by a stub that either starts a
# session or refuses, the way tmux refuses without a UTF-8 locale.
run_mode()
{
    local hook="$1" mux="$2" mux_works="$3" body
    body="$(extract_shell_function "$hook" xcat_console_mode)" ||
        { echo "xcat_console_mode() not found in $hook" >&2; return 99; }
    (
        eval "$body"
        eval "$mux() {
            [ \"\$mux_works\" = 1 ] && return 0
            echo '$mux: need UTF-8 locale (LC_CTYPE) but have ANSI_X3.4-1968' >&2
            return 1
        }"
        xcat_console_mode
    ) 2>/dev/null
}

# The hook reads the mode once and guards the doxcat loop with it.
assert_hook_guards_doxcat()
{
    local hook="$1" mux="$2"
    grep -qx 'XCAT_CONSOLE_MODE="$(xcat_console_mode)"' "$hook"
    grep -qFx "if [ \"\$XCAT_CONSOLE_MODE\" = \"$mux\" ]; then" "$hook"
    grep -A1 '^else$' "$hook" | grep -qx '    while :; do doxcat; sleep 5; done'
}

@test "the el hook leaves no unguarded tmux loop and exports a UTF-8 locale" {
    # tmux exits under the C locale, so an unguarded tmux loop never reaches doxcat.
    refute_grep -q '^while :; do tmux attach-session' "$EL_HOOK"
    grep -qx 'export LC_ALL=C.UTF-8' "$EL_HOOK"
}

@test "el: xcat_console_mode reports the mode tmux can actually provide" {
    [ "$(run_mode "$EL_HOOK" tmux 0)" = direct ]
    [ "$(run_mode "$EL_HOOK" tmux 1)" = tmux ]
}

@test "el: the hook resolves the console mode once and runs doxcat directly without tmux" {
    assert_hook_guards_doxcat "$EL_HOOK" tmux
}

@test "ubuntu: xcat_console_mode reports the mode screen can actually provide" {
    [ "$(run_mode "$UBUNTU_HOOK" screen 0)" = direct ]
    [ "$(run_mode "$UBUNTU_HOOK" screen 1)" = screen ]
}

@test "ubuntu: the hook resolves the console mode once and runs doxcat directly without screen" {
    assert_hook_guards_doxcat "$UBUNTU_HOOK" screen
}
