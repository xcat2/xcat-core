#!/usr/bin/env bats
#
# nic_cfg.sh show must dump the file NetworkManager actually keeps the connection in.
#
# Regression: nm_show looked for a keyfile under /etc/NetworkManager/system-connections and
# dumped nothing when it found none. On EL8 the ifcfg-rh plugin owns an xCAT connection and
# writes /etc/sysconfig/network-scripts/ifcfg-xcat-<nic>, which is where configeth puts an
# extra param such as CONNECTED_MODE. So confignetwork_secondarynic_nicextraparams_updatenode
# read a dump with no extra params in it and failed on EL8 while passing on EL9 and EL10.
#
# nmcli and systemctl are stubbed, so no NetworkManager is needed and nothing on the host is
# read or written.

load 'helpers/shell_source'

UUID=4f99157f-c20a-4a05-bb48-f073abbf027a

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/nic_cfg.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$BIN"
    printf '#!/bin/sh\nexit 0\n' >"$BIN/systemctl"
    chmod 0755 "$BIN/systemctl"
    export PATH="$BIN:$PATH"
}

# Write an nmcli that answers for one connection kept in $1, reporting $2 as 802-3-ethernet.mtu.
stub_nmcli()
{
    local file="$1" ethernet_mtu="$2"
    cat >"$BIN/nmcli" <<EOF
#!/bin/sh
args="\$*"
case "\$args" in
    "-t -f NAME,DEVICE connection show --active") echo "xcat-ens4:ens4" ;;
    "-t -f NAME,DEVICE connection show")         echo "xcat-ens4:ens4" ;;
    "-g connection.uuid connection show xcat-ens4") echo "${UUID}" ;;
    "-t -f UUID,FILENAME connection show")       echo "${UUID}:${file}" ;;
    "-g ipv4.method connection show xcat-ens4")  echo "manual" ;;
    "-g ipv4.addresses connection show xcat-ens4") echo "11.1.0.100/16" ;;
    "-g 802-3-ethernet.mtu connection show xcat-ens4") echo "${ethernet_mtu}" ;;
    *) echo "unexpected nmcli \$args" >&2; exit 1 ;;
esac
EOF
    chmod 0755 "$BIN/nmcli"
}

@test "an ifcfg-backed connection has its ifcfg file dumped" {
    local ifcfg="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4"
    cat >"$ifcfg" <<'EOF'
DEVICE=ens4
BOOTPROTO=none
IPADDR=11.1.0.100
PREFIX=16
CONNECTED_MODE=yes
EOF
    stub_nmcli "$ifcfg" ""

    run "$SCRIPT" show ens4

    [ "$status" -eq 0 ]
    [[ "$output" == *"NAME=xcat-ens4"* ]]
    [[ "$output" == *"IPADDR=11.1.0.100"* ]]
    [[ "$output" == *"CONNECTED_MODE=yes"* ]]
}

@test "an ifcfg-backed connection reports the MTU the ifcfg file names" {
    local ifcfg="${BATS_TEST_TMPDIR}/ifcfg-xcat-ens4"
    printf 'DEVICE=ens4\nMTU=1496\n' >"$ifcfg"
    stub_nmcli "$ifcfg" ""

    run "$SCRIPT" show ens4

    [ "$status" -eq 0 ]
    [[ "$output" == *"MTU=1496"* ]]
}

@test "a keyfile-backed connection still has its keyfile dumped" {
    local keyfile="${BATS_TEST_TMPDIR}/xcat-ens4.nmconnection"
    cat >"$keyfile" <<EOF
[connection]
id=xcat-ens4
uuid=${UUID}

[ethernet]
mtu=1496

[user]
xcat.CONNECTED_MODE=yes
EOF
    stub_nmcli "$keyfile" "1496"

    run "$SCRIPT" show ens4

    [ "$status" -eq 0 ]
    [[ "$output" == *"MTU=1496"* ]]
    [[ "$output" == *"xcat.CONNECTED_MODE=yes"* ]]
}
