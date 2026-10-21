#!/usr/bin/env bats
#
# makenamed.conf builds the forwarder list of a service node's named from /etc/resolv.conf.
#
# On a host managed by systemd-resolved that file holds the 127.0.0.53 stub, and the stub points
# back at this named for the link. forward-only to it is a loop: the service node answers
# nothing, and every compute node behind it fails to resolve. Measured on xcat22-sn, where
# "dig @<sn> xcat22-sn.xcat22.lab" returned nothing while the same query to the management node
# answered. The EL service node has the real upstream in /etc/resolv.conf, which is why it works.
#
# systemd-resolved writes the real servers to /run/systemd/resolve/resolv.conf.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-server/sbin/makenamed.conf')"
    RESOLV="${BATS_TEST_TMPDIR}/resolv.conf"
    UPLINK="${BATS_TEST_TMPDIR}/uplink.conf"
    # MAKENAMED_LIB stops the script before it writes anything, so only the routine is loaded.
    MAKENAMED_LIB=1 . "$SCRIPT"
    export -f forwarder_addresses _fa_usable
}

@test "a real nameserver is a forwarder" {
    printf 'nameserver 192.168.222.1\nsearch xcat22.lab\n' >"$RESOLV"
    run forwarder_addresses "$RESOLV" "$UPLINK"
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.222.1" ]
}

@test "the systemd-resolved stub is not a forwarder, and the uplink answers instead" {
    printf 'nameserver 127.0.0.53\noptions edns0 trust-ad\n' >"$RESOLV"
    printf 'nameserver 192.168.222.1\nsearch xcat22.lab\n' >"$UPLINK"
    run forwarder_addresses "$RESOLV" "$UPLINK"
    [ "$status" -eq 0 ]
    [ "$output" = "192.168.222.1" ]
}

@test "any loopback address is rejected, not only the stub" {
    printf 'nameserver 127.0.0.1\nnameserver ::1\n' >"$RESOLV"
    printf 'nameserver 10.0.0.1\n' >"$UPLINK"
    run forwarder_addresses "$RESOLV" "$UPLINK"
    [ "$output" = "10.0.0.1" ]
}

@test "several real nameservers are all forwarders, in order" {
    printf 'nameserver 192.168.222.1\nnameserver 10.0.0.2\n' >"$RESOLV"
    run forwarder_addresses "$RESOLV" "$UPLINK"
    [ "$output" = "192.168.222.1
10.0.0.2" ]
}

@test "a real nameserver wins over the uplink, which is only the fallback" {
    printf 'nameserver 192.168.222.1\n' >"$RESOLV"
    printf 'nameserver 10.9.9.9\n' >"$UPLINK"
    run forwarder_addresses "$RESOLV" "$UPLINK"
    [ "$output" = "192.168.222.1" ]
}

@test "no usable address anywhere prints nothing rather than a blank forwarder" {
    printf 'nameserver 127.0.0.53\n' >"$RESOLV"
    : >"$UPLINK"
    # Count the lines. A blank line reaches named.conf as an empty forwarder entry, which bind
    # rejects as a syntax error, and $output cannot tell one from no output at all.
    run bash -c "forwarder_addresses '$RESOLV' '$UPLINK' | wc -l"
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "an absent uplink file is not an error" {
    printf 'nameserver 127.0.0.53\n' >"$RESOLV"
    run forwarder_addresses "$RESOLV" "${BATS_TEST_TMPDIR}/absent"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# named runs as "bind" on Debian and writes its managed-keys database into the configured
# directory. /var/named is created root-owned, so the write fails, DNSSEC initialisation fails
# with it, and the server answers NXDOMAIN to every query -- including forwarded ones, which is
# how a correct forwarder list still resolved nothing on xcat22-sn.

@test "Ubuntu names the directory its named can write" {
    printf 'DISTRIB_ID=Ubuntu\nDISTRIB_RELEASE=24.04\n' >"${BATS_TEST_TMPDIR}/lsb"
    run named_directory "${BATS_TEST_TMPDIR}/lsb" "${BATS_TEST_TMPDIR}/absent-os" "${BATS_TEST_TMPDIR}/absent-suse"
    [ "$output" = "/var/cache/bind" ]
}

@test "SLES keeps its own directory" {
    : >"${BATS_TEST_TMPDIR}/lsb"
    printf 'ID="sles"\n' >"${BATS_TEST_TMPDIR}/os"
    run named_directory "${BATS_TEST_TMPDIR}/lsb" "${BATS_TEST_TMPDIR}/os" "${BATS_TEST_TMPDIR}/absent-suse"
    [ "$output" = "/var/lib/named" ]
}

@test "EL keeps /var/named" {
    : >"${BATS_TEST_TMPDIR}/lsb"
    printf 'ID="almalinux"\n' >"${BATS_TEST_TMPDIR}/os"
    run named_directory "${BATS_TEST_TMPDIR}/lsb" "${BATS_TEST_TMPDIR}/os" "${BATS_TEST_TMPDIR}/absent-suse"
    [ "$output" = "/var/named" ]
}

@test "an absent lsb-release is not Ubuntu" {
    printf 'ID="almalinux"\n' >"${BATS_TEST_TMPDIR}/os"
    run named_directory "${BATS_TEST_TMPDIR}/absent-lsb" "${BATS_TEST_TMPDIR}/os" "${BATS_TEST_TMPDIR}/absent-suse"
    [ "$output" = "/var/named" ]
}
