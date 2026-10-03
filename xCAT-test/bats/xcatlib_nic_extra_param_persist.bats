#!/usr/bin/env bats
#
# nicextraparams that NetworkManager does not model survive only if configeth writes them into
# the file NM reports, after the activation that re-serializes it. The keyfile store was already
# covered; an ifcfg store was not, so CONNECTED_MODE=yes never reached the profile on el8 and
# openEuler (confignetwork_secondarynic_nicextraparams_updatenode).
#
# `nmcli` is stubbed, so nothing on the host is read.

load 'helpers/shell_source'

setup()
{
    LIB="$(require_repo_file 'xCAT/postscripts/xcatlib.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$BIN"
    export PATH="$BIN:$PATH"
}

# Write an `nmcli` that reports $2 as the file for connection $1.
stub_nmcli()
{
    cat >"$BIN/nmcli" <<STUB
#!/bin/sh
case "\$*" in
    *"-g connection.uuid"*) printf '%s\n' 'c9b049e1-abe6-4df3-9d76-d156d8c764c3' ;;
    *"-t -f UUID,FILENAME"*) printf '%s\n' 'c9b049e1-abe6-4df3-9d76-d156d8c764c3:$2' ;;
esac
STUB
    chmod 0755 "$BIN/nmcli"
}

stub_nmcli_no_connection()
{
    printf '#!/bin/sh\nexit 1\n' >"$BIN/nmcli"
    chmod 0755 "$BIN/nmcli"
}

@test "the connection file comes from NetworkManager, not from the connection name" {
    # NM suffixes the file when one of the plain name already exists.
    stub_nmcli xcat-ens4 /etc/sysconfig/network-scripts/ifcfg-xcat-ens4-1
    source "$LIB"
    run xcat_nm_conn_file xcat-ens4
    [ "$status" -eq 0 ]
    [ "$output" = "/etc/sysconfig/network-scripts/ifcfg-xcat-ens4-1" ]
}

@test "a connection NetworkManager does not know has no file" {
    stub_nmcli_no_connection
    source "$LIB"
    run xcat_nm_conn_file xcat-ens4
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "an ifcfg profile keeps the key as the profile writes it" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4-1"
    printf 'TYPE=Ethernet\nNAME=xcat-ens4\n' >"$f"
    source "$LIB"
    run xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$status" -eq 0 ]
    grep -qx 'CONNECTED_MODE=yes' "$f"
}

@test "an ifcfg profile gains no [user] section and no xcat prefix" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4"
    printf 'TYPE=Ethernet\n' >"$f"
    source "$LIB"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    ! grep -q '\[user\]' "$f"
    ! grep -q 'xcat\.CONNECTED_MODE' "$f"
}

@test "a keyfile keeps the key under [user] with the xcat prefix" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    printf '[connection]\nid=xcat-ens4\n' >"$f"
    source "$LIB"
    run xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$status" -eq 0 ]
    grep -q '^\[user\]' "$f"
    grep -qx 'xcat.CONNECTED_MODE=yes' "$f"
    ! grep -qx 'CONNECTED_MODE=yes' "$f"
}

@test "writing the same key twice does not duplicate it" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4-1"
    printf 'TYPE=Ethernet\n' >"$f"
    source "$LIB"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(grep -cx 'CONNECTED_MODE=yes' "$f")" -eq 1 ]
}

@test "a keyfile written twice keeps one [user] section and one key" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    printf '[connection]\nid=xcat-ens4\n' >"$f"
    source "$LIB"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(grep -c '^\[user\]' "$f")" -eq 1 ]
    [ "$(grep -cx 'xcat.CONNECTED_MODE=yes' "$f")" -eq 1 ]
}

@test "a file that does not exist is refused" {
    source "$LIB"
    run xcat_persist_nic_extra_param "${BATS_TEST_TMPDIR}/absent" CONNECTED_MODE yes
    [ "$status" -ne 0 ]
}
