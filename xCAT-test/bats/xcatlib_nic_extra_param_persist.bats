#!/usr/bin/env bats
# A nicextraparams key NM does not model survives only if configeth writes it into the file
# NM reports. nmcli is a shell function here, so nothing on the host is read.

load 'helpers/shell_source'

UUID='c9b049e1-abe6-4df3-9d76-d156d8c764c3'

setup()
{
    source "$(require_repo_file 'xCAT/postscripts/xcatlib.sh')"
}

# stub_nmcli <connection> <file> -- NM knows <connection> and reports <file> for it.
stub_nmcli()
{
    NM_CONN="$1"
    NM_FILE="$2"
    nmcli()
    {
        case "$*" in
            "-g connection.uuid connection show $NM_CONN") printf '%s\n' "$UUID" ;;
            "-t -f UUID,FILENAME connection show")
                printf '%s\n' '0f9a1c55-0000-4000-8000-000000000001:/etc/sysconfig/network-scripts/ifcfg-eth0'
                printf '%s:%s\n' "$UUID" "$NM_FILE"
                ;;
            *) return 10 ;;
        esac
    }
}

@test "the connection file comes from NetworkManager, not from the connection name" {
    # NM suffixes the file when one of the plain name already exists.
    stub_nmcli xcat-ens4 /etc/sysconfig/network-scripts/ifcfg-xcat-ens4-1
    run xcat_nm_conn_file xcat-ens4
    [ "$status" -eq 0 ]
    [ "$output" = "/etc/sysconfig/network-scripts/ifcfg-xcat-ens4-1" ]
}

@test "a connection NetworkManager does not know has no file" {
    stub_nmcli xcat-other /etc/sysconfig/network-scripts/ifcfg-xcat-other
    run xcat_nm_conn_file xcat-ens4
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "openEuler uses the keyfile store only when NM reports a keyfile" {
    networkmanager_active=1
    stub_nmcli xcat-ens4 /etc/NetworkManager/system-connections/xcat-ens4.nmconnection
    xcat_uses_nm_keyfile openeuler22.03 xcat-ens4
    stub_nmcli xcat-ens4 /etc/sysconfig/network-scripts/ifcfg-xcat-ens4
    run xcat_uses_nm_keyfile openeuler22.03 xcat-ens4
    [ "$status" -ne 0 ]
}

@test "configeth's repair writes the key into an ifcfg profile NM reports" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4-1"
    printf 'TYPE=Ethernet\nNAME=xcat-ens4\n' >"$f"
    stub_nmcli xcat-ens4 "$f"
    OSVER=openeuler20.03 networkmanager_active=1
    run xcat_nm_persist_nic_extra_params xcat-ens4 'CONNECTED_MODE=yes MTU=1500' default
    [ "$status" -eq 0 ]
    grep -qx 'CONNECTED_MODE=yes' "$f"
    grep -qx 'MTU=1500' "$f"
    refute_grep -q '\[user\]' "$f"
    refute_grep -q 'xcat\.' "$f"
}

@test "configeth's repair writes the key into a keyfile NM reports" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4-${UUID}.nmconnection"
    printf '[connection]\nid=xcat-ens4\n' >"$f"
    stub_nmcli xcat-ens4 "$f"
    OSVER=openeuler24.03 networkmanager_active=1
    run xcat_nm_persist_nic_extra_params xcat-ens4 'CONNECTED_MODE=yes'
    [ "$status" -eq 0 ]
    [ "$(sed -n '/^\[user\]$/,$p' "$f" | grep -cx 'xcat.CONNECTED_MODE=yes')" -eq 1 ]
    refute_grep -qx 'CONNECTED_MODE=yes' "$f"
}

@test "configeth's repair names the connection when NM reports no file" {
    stub_nmcli xcat-other /etc/sysconfig/network-scripts/ifcfg-xcat-other
    run xcat_nm_persist_nic_extra_params xcat-ens4 'CONNECTED_MODE=yes'
    [ "$status" -eq 1 ]
    [[ "$output" == *"NetworkManager reports no file for 'xcat-ens4'"* ]]
}

@test "configeth's repair does nothing when no IP carries extra params" {
    nmcli() { echo "nmcli must not run" >&2; return 10; }
    run xcat_nm_persist_nic_extra_params xcat-ens4 default ''
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "an ifcfg value is replaced, not duplicated, and a similar key is left alone" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4"
    printf 'TYPE=Ethernet\nXCONNECTED_MODE=keep\nCONNECTED_MODE=no\nCONNECTED_MODE_X=keep\n' >"$f"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(grep -c '^CONNECTED_MODE=' "$f")" -eq 1 ]
    grep -qx 'CONNECTED_MODE=yes' "$f"
    grep -qx 'XCONNECTED_MODE=keep' "$f"
    grep -qx 'CONNECTED_MODE_X=keep' "$f"
}

@test "a keyfile value is replaced in [user], not duplicated, and a similar key is left alone" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    printf '[connection]\nid=xcat-ens4\n\n[user]\nxcat.CONNECTED_MODE=no\nxcat.CONNECTED_MODE_X=keep\n\n[ipv4]\nmethod=manual\n' >"$f"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(grep -c '^\[user\]' "$f")" -eq 1 ]
    [ "$(grep -c '^xcat\.CONNECTED_MODE=' "$f")" -eq 1 ]
    [ "$(sed -n '/^\[user\]$/,/^\[ipv4\]$/p' "$f" | grep -cx 'xcat.CONNECTED_MODE=yes')" -eq 1 ]
    grep -qx 'xcat.CONNECTED_MODE_X=keep' "$f"
}

@test "a keyfile with a [user] section elsewhere gets the key inside that section" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    printf '[connection]\nid=xcat-ens4\n[user]\nxcat.other=1\n[ipv4]\nmethod=manual\n' >"$f"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(sed -n '/^\[user\]$/,/^\[ipv4\]$/p' "$f" | grep -cx 'xcat.CONNECTED_MODE=yes')" -eq 1 ]
    [ "$(stat -c %a "$f")" = 600 ]
}

@test "an ifcfg profile without a final newline keeps its last line" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4"
    printf 'TYPE=Ethernet\nNAME=xcat-ens4' >"$f"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    grep -qx 'NAME=xcat-ens4' "$f"
    grep -qx 'CONNECTED_MODE=yes' "$f"
}

@test "a keyfile ending in [user] without a final newline keeps the section" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    printf '[connection]\nid=xcat-ens4\n[user]' >"$f"
    xcat_persist_nic_extra_param "$f" CONNECTED_MODE yes
    [ "$(grep -cx '\[user\]' "$f")" -eq 1 ]
    grep -qx 'xcat.CONNECTED_MODE=yes' "$f"
}

@test "a file that does not exist is refused" {
    run xcat_persist_nic_extra_param "${BATS_TEST_TMPDIR}/absent" CONNECTED_MODE yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"no profile file '${BATS_TEST_TMPDIR}/absent'"* ]]
    [ ! -e "${BATS_TEST_TMPDIR}/absent" ]
}
