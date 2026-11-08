#!/usr/bin/env bats
#
# Net init ends when the boot nic can reach xcatd. xcatd is on one family, so a node that has an
# address of the OTHER family is not ready: on a dual stack provisioning network it would go on
# to getcert and getdestiny with no route to the management node. The earlier form ended the wait
# on an address of either family, which was right for an IPv6-only cell and wrong here.

load 'helpers/shell_source'

setup()
{
    DOXCAT="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/doxcat')"
    BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$BIN"
    ADDR="${BATS_TEST_TMPDIR}/addr"; mkdir -p "$ADDR"
    : >"$ADDR/v4"; : >"$ADDR/v6"
    cat >"$BIN/ip" <<SH
#!/bin/sh
case "\$1" in
    -4) cat "$ADDR/v4" ;;
    -6) cat "$ADDR/v6" ;;
esac
SH
    chmod 0755 "$BIN/ip"
    LIB="${BATS_TEST_TMPDIR}/lib.sh"
    for f in genesis_nic_has_global_v6 genesis_nic_has_global_v4 genesis_nic_has_address; do
        extract_shell_function "$DOXCAT" "$f" >>"$LIB" || {
            echo "could not extract $f" >&2; return 1; }
    done
}

has_v4() { printf '2: boot0 inet 192.0.2.20/24 scope global\n' >"$ADDR/v4"; }
has_v6() { printf '2: boot0 inet6 2001:db8:188::20/64 scope global\n' >"$ADDR/v6"; }

ready()
{
    run env PATH="$BIN:$PATH" XCATMASTER="$1" bash -c \
        ". '$LIB'; genesis_nic_has_address boot0 && echo READY || echo WAIT"
    [ "$status" -eq 0 ]
}

@test "an IPv6 xcatd is not reached by an IPv4 address alone" {
    has_v4
    ready '2001:db8:188::1'
    [ "$output" = WAIT ]
}

@test "an IPv6 xcatd is reached once the IPv6 address arrives" {
    has_v6
    ready '2001:db8:188::1'
    [ "$output" = READY ]
}

@test "an IPv4 xcatd is not reached by an IPv6 address alone" {
    has_v6
    ready '192.168.1.1'
    [ "$output" = WAIT ]
}

@test "an IPv4 xcatd is reached once the IPv4 address arrives" {
    has_v4
    ready '192.168.1.1'
    [ "$output" = READY ]
}

@test "with no xcatd address an address of either family ends the wait" {
    has_v6
    ready ''
    [ "$output" = READY ]
}

@test "a link-local address alone never ends the wait" {
    printf '2: boot0 inet6 fe80::1/64 scope link\n' >"$ADDR/v6"
    ready '2001:db8:188::1'
    [ "$output" = WAIT ]
}
