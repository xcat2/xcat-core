#!/usr/bin/env bats
#
# The Ubuntu 26.04 initramfs runs dracut 110 with systemd-networkd. Two conditions must hold
# before its initqueue fetches the root image:
#   - the boot NIC gets a DHCPv4 lease, and
#   - the initqueue has a finished condition, or it ends before it runs the settled hooks.

load 'helpers/shell_source'

setup()
{
    INSTALL="$(require_repo_file 'xCAT-server/share/xcat/netboot/ubuntu/dracut/install.netboot')"
    MOD="$(dirname "$INSTALL")"
    LOG="${BATS_TEST_TMPDIR}/installed"
    : >"$LOG"
    HOOKS="${BATS_TEST_TMPDIR}/hooks"
    mkdir -p "$HOOKS/initqueue/finished"
}

# Run install.netboot as dracut does, with its helpers stubbed to record what it asks for.
run_install()
{
    run env MODDIR="$MOD" LOG="$LOG" bash -c '
        moddir=$MODDIR
        dracut_install() { :; }
        inst()           { :; }
        inst_hook()      { :; }
        inst_simple()    { printf "inst_simple %s %s\n" "$1" "$2" >>"$LOG"; }
        . "$MODDIR/install.netboot"
    '
}

# Source xcat-cmdline.sh as dracut-cmdline does, with hookdir set.
run_cmdline()
{
    run env MODDIR="$MOD" HOOKS="$HOOKS" bash -c '
        hookdir=$HOOKS
        . "$MODDIR/xcat-cmdline.sh"
        printf "root=%s rootok=%s netroot=%s\n" "$root" "$rootok" "$netroot"
    '
}

@test "the cmdline hook gives the initqueue a finished condition in dracut's hook directory" {
    run_cmdline
    [ "$status" -eq 0 ]
    [ "$output" = "root=1 rootok=1 netroot=xcat" ]
    [ -f "$HOOKS/initqueue/finished/xcatroot.sh" ]
}

@test "the finished condition holds only after the root image is unpacked" {
    run_cmdline
    [ "$status" -eq 0 ]
    newroot="${BATS_TEST_TMPDIR}/sysroot"
    mkdir -p "$newroot"
    run env NEWROOT="$newroot" sh "$HOOKS/initqueue/finished/xcatroot.sh"
    [ "$status" -ne 0 ]
    mkdir "$newroot/proc"
    run env NEWROOT="$newroot" sh "$HOOKS/initqueue/finished/xcatroot.sh"
    [ "$status" -eq 0 ]
}

@test "the module turns on DHCPv4 for the network that systemd makes from BOOTIF=" {
    run_install
    [ "$status" -eq 0 ]
    line="$(grep -E '^inst_simple .* /etc/systemd/network/70-BOOTIF\.network\.d/[^/]+\.conf$' "$LOG")"
    [ -n "$line" ]
    src="$(printf '%s\n' "$line" | awk '{print $2}')"
    [ "$(dirname "$src")" = "$MOD" ]
    [ -f "$src" ]
    run awk '/^\[/{s=$0} s=="[Network]" && /^DHCP=/{print}' "$src"
    [ "$output" = "DHCP=ipv4" ]
}
