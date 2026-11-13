#!/usr/bin/env bats
#
# The cases restarted the DHCPv4 server by probing kea-dhcp4 and falling back to
# isc-dhcp-server on Ubuntu. xCAT's Kea unit on Debian and Ubuntu is kea-dhcp4-server, so the
# probe was false and the fallback named a unit that is not installed there:
# reg_linux_diskless_installation_hierarchy failed on "Unit isc-dhcp-server.service not found"
# with rc 5, measured on xcat24-mn, Ubuntu 24.04.4.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/restart_dhcp.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "$BIN"
    ACTED="${BATS_TEST_TMPDIR}/acted"
    : >"$ACTED"
}

# Stand in for systemctl, reporting exactly one unit active and recording what was restarted.
stub_systemctl()
{
    local active="$1"
    cat >"$BIN/systemctl" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$ACTED"
case "\$1 \$2" in
    "is-active $active") exit 0 ;;
    is-active*)          exit 3 ;;
    "restart $active")   exit 0 ;;
    restart*)            printf 'Unit %s.service not found.\n' "\$2" >&2; exit 5 ;;
esac
SH
    chmod 0755 "$BIN/systemctl"
}

run_helper()
{
    run env PATH="$BIN:$PATH" bash "$SCRIPT"
}

@test "the Ubuntu Kea unit is restarted" {
    stub_systemctl kea-dhcp4-server
    run_helper
    [ "$status" -eq 0 ]
    grep -qx 'restart kea-dhcp4-server' "$ACTED"
    refute_grep -q 'isc-dhcp-server' "$ACTED"
}

@test "the EL Kea unit is restarted" {
    stub_systemctl kea-dhcp4
    run_helper
    [ "$status" -eq 0 ]
    grep -qx 'restart kea-dhcp4' "$ACTED"
}

@test "an ISC backend is still restarted" {
    stub_systemctl isc-dhcp-server
    run_helper
    [ "$status" -eq 0 ]
    grep -qx 'restart isc-dhcp-server' "$ACTED"
}

@test "the EL ISC unit is still restarted" {
    stub_systemctl dhcpd
    run_helper
    [ "$status" -eq 0 ]
    grep -qx 'restart dhcpd' "$ACTED"
}

@test "no active DHCPv4 server is an error that names what was tried" {
    stub_systemctl none-of-them
    run_helper
    [ "$status" -ne 0 ]
    [[ "$output" == *"no DHCPv4 server is active"* ]]
    [[ "$output" == *kea-dhcp4-server* ]]
    refute_grep -q '^restart' "$ACTED"
}

@test "--print-unit names the Ubuntu Kea unit and restarts nothing" {
    stub_systemctl kea-dhcp4-server
    run env PATH="$BIN:$PATH" bash "$SCRIPT" --print-unit
    [ "$status" -eq 0 ]
    [ "$output" = kea-dhcp4-server ]
    refute_grep -q '^restart' "$ACTED"
}

@test "--print-unit names an ISC backend, so a caller can tell it from Kea" {
    stub_systemctl dhcpd
    run env PATH="$BIN:$PATH" bash "$SCRIPT" --print-unit
    [ "$status" -eq 0 ]
    [ "$output" = dhcpd ]
}

@test "--print-unit fails when no DHCPv4 server is active" {
    stub_systemctl none-of-them
    run env PATH="$BIN:$PATH" bash "$SCRIPT" --print-unit
    [ "$status" -ne 0 ]
}
