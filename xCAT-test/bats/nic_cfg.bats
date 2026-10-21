#!/usr/bin/env bats
# nic_cfg.sh show must print the profile NM reports, whichever store holds it, so a case can
# match a key NM does not model. nmcli is a shell function here.

load 'helpers/shell_source'

UUID='c9b049e1-abe6-4df3-9d76-d156d8c764c3'

setup()
{
    source "$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/nic_cfg.sh')"
}

# stub_nmcli <file> -- NM binds xcat-ens4 to ens4 and reports <file> for it.
stub_nmcli()
{
    NM_FILE="$1"
    nmcli()
    {
        case "$*" in
            "-t -f NAME,DEVICE connection show --active") printf '%s\n' 'xcat-ens4:ens4' ;;
            "-g ipv4.method connection show xcat-ens4") printf '%s\n' manual ;;
            "-g ipv4.addresses connection show xcat-ens4") printf '%s\n' '100.0.0.9/16' ;;
            "-g 802-3-ethernet.mtu connection show xcat-ens4") printf '%s\n' auto ;;
            "-g connection.uuid connection show xcat-ens4") printf '%s\n' "$UUID" ;;
            "-t -f UUID,FILENAME connection show") printf '%s:%s\n' "$UUID" "$NM_FILE" ;;
            *) return 10 ;;
        esac
    }
}

@test "show prints an ifcfg profile that NM reports" {
    f="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4-1"
    printf 'TYPE=Ethernet\nCONNECTED_MODE=yes\n' >"$f"
    stub_nmcli "$f"
    run nm_show ens4
    [ "$status" -eq 0 ]
    [[ "$output" == *"# --- $f ---"* ]]
    [[ "$output" == *$'\nCONNECTED_MODE=yes'* ]]
    [[ "$output" == *$'\nIPADDR=100.0.0.9'* ]]
}

@test "show prints a keyfile that NM reports" {
    f="${BATS_TEST_TMPDIR}/xcat-ens4-${UUID}.nmconnection"
    printf '[connection]\nid=xcat-ens4\n[user]\nxcat.CONNECTED_MODE=yes\n' >"$f"
    stub_nmcli "$f"
    run nm_show ens4
    [ "$status" -eq 0 ]
    [[ "$output" == *"# --- $f ---"* ]]
    [[ "$output" == *$'\nxcat.CONNECTED_MODE=yes'* ]]
}
