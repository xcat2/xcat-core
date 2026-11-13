#!/usr/bin/env bats
#
# dracut dispatches a netroot= handler from network-legacy's ifup. Ubuntu 25.10 and later ship no
# network-legacy, so `network` resolves through systemd-networkd and nothing calls /sbin/netroot.
# On 26.04 the initramfs then fetches no root: measured on xcat32-cn, zero DHCP from the initrd,
# zero httpd requests for rootimg.cpio.gz, and dracut in emergency mode 3.3 seconds in.

load 'helpers/shell_source'

setup()
{
    INSTALL="$(require_repo_file 'xCAT-server/share/xcat/netboot/ubuntu/dracut/install.netboot')"
    MOD="$(dirname "$INSTALL")"
    LOG="${BATS_TEST_TMPDIR}/installed"
    : >"$LOG"
}

# Run install.netboot the way dracut does: as a shell fragment with dracut's helpers in scope.
# Recording what it asks for is the behaviour under test, so the helpers are stubs.
run_install()
{
    local extra="${1:-}"
    run env MODDIR="$MOD" LOG="$LOG" EXTRA="$extra" bash -c '
        moddir=$MODDIR
        dracut_install() { printf "dracut_install %s\n" "$*" >>"$LOG"; }
        inst()           { printf "inst %s %s\n" "$1" "$2" >>"$LOG"; }
        inst_hook()      { printf "inst_hook %s %s %s\n" "$1" "$2" "$3" >>"$LOG"; }
        inst_simple()    { printf "inst_simple %s %s\n" "$1" "$2" >>"$LOG"; }
        [ -n "$EXTRA" ] && eval "$EXTRA"
        . "$MODDIR/install.netboot"
    '
}

@test "the root handler is registered on an interface coming online" {
    run_install
    [ "$status" -eq 0 ]
    grep -q '^inst_hook initqueue/online 90 .*/xcat-online\.sh$' "$LOG"
}

@test "the root handler itself is installed where the hook calls it" {
    run_install
    grep -q '^inst .*/xcatroot /sbin/xcatroot$' "$LOG"
}

@test "the cmdline hook that names the netroot is still installed" {
    run_install
    grep -q '^inst_hook cmdline 10 .*/xcat-cmdline\.sh$' "$LOG"
}

@test "the legacy dispatcher is still taken when dracut ships one" {
    # network-legacy exists on EL, and nothing here should stop that path working.
    mkdir -p "${BATS_TEST_TMPDIR}/40network"
    : >"${BATS_TEST_TMPDIR}/40network/netroot.sh"
    run_install "moddir=${BATS_TEST_TMPDIR}/fake; mkdir -p \$moddir; cp -r $MOD/. \$moddir/; cp -r ${BATS_TEST_TMPDIR}/40network \$(dirname \$moddir)/40network"
    [ "$status" -eq 0 ]
    grep -q '^inst .*/netroot\.sh /sbin/netroot$' "$LOG"
}

@test "the online hook calls the handler with dracut's three arguments" {
    local hook="$MOD/xcat-online.sh"
    [ -x "$hook" ]
    # Drive the hook with a stub handler and assert what it passes. The marker it writes is
    # redirected too: an initramfs path is absolute, and a test must not write the real /tmp.
    local bin="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$bin/sbin" "${BATS_TEST_TMPDIR}/lib"
    cat >"${BATS_TEST_TMPDIR}/lib/dracut-lib.sh" <<'LIB'
getarg() { return 1; }
LIB
    cat >"$bin/sbin/xcatroot" <<SH
#!/bin/sh
printf '%s\n' "\$*" >"${BATS_TEST_TMPDIR}/called"
SH
    chmod 0755 "$bin/sbin/xcatroot"
    run env NEWROOT=/sysroot netroot=xcat bash -c "
        cd '${BATS_TEST_TMPDIR}'
        sed -e 's#/lib/dracut-lib.sh#${BATS_TEST_TMPDIR}/lib/dracut-lib.sh#' \
            -e 's#/sbin/xcatroot#${bin}/sbin/xcatroot#g' \
            -e 's#/tmp/xcat.rootimg.done#${BATS_TEST_TMPDIR}/done#' '$hook' > ./hook.sh
        bash -c '. ./hook.sh eth0'"
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/called")" = 'eth0 xcat /sysroot' ]
}

@test "a second interface does not fetch the image again" {
    local hook="$MOD/xcat-online.sh"
    local bin="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$bin/sbin" "${BATS_TEST_TMPDIR}/lib"
    printf 'getarg() { return 1; }\n' >"${BATS_TEST_TMPDIR}/lib/dracut-lib.sh"
    cat >"$bin/sbin/xcatroot" <<SH
#!/bin/sh
printf 'x\n' >>"${BATS_TEST_TMPDIR}/count"
SH
    chmod 0755 "$bin/sbin/xcatroot"
    run env NEWROOT=/sysroot netroot=xcat bash -c "
        cd '${BATS_TEST_TMPDIR}'
        sed -e 's#/lib/dracut-lib.sh#${BATS_TEST_TMPDIR}/lib/dracut-lib.sh#' \
            -e 's#/sbin/xcatroot#${bin}/sbin/xcatroot#g' \
            -e 's#/tmp/xcat.rootimg.done#${BATS_TEST_TMPDIR}/done#' '$hook' > ./hook.sh
        bash -c '. ./hook.sh eth0; . ./hook.sh eth1'"
    [ "$status" -eq 0 ]
    [ "$(wc -l < "${BATS_TEST_TMPDIR}/count")" -eq 1 ]
}

@test "the hook leaves its caller running, because dracut sources it" {
    # source_all runs `. "$f" "$@"`, so an `exit` in a hook ends networkd-run.sh, which is the
    # script bringing the network up. The early return path is the one that would do it.
    local hook="$MOD/xcat-online.sh"
    mkdir -p "${BATS_TEST_TMPDIR}/lib"
    printf 'getarg() { return 1; }\n' >"${BATS_TEST_TMPDIR}/lib/dracut-lib.sh"
    run env bash -c "
        cd '${BATS_TEST_TMPDIR}'
        sed -e 's#/lib/dracut-lib.sh#${BATS_TEST_TMPDIR}/lib/dracut-lib.sh#' \
            -e 's#/tmp/xcat.rootimg.done#${BATS_TEST_TMPDIR}/done#' '$hook' > ./hook.sh
        : > ./done
        sh -c '. ./hook.sh eth0; echo CALLER-SURVIVED'"
    [ "$status" -eq 0 ]
    [[ "$output" == *CALLER-SURVIVED* ]]
}
