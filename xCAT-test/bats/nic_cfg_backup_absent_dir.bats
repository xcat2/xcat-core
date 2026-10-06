#!/usr/bin/env bats
# nic_cfg.sh backup must succeed on a node with no persistent network configuration.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/nic_cfg.sh')"
    export BACKUP="${BATS_TEST_TMPDIR}/backupnet"
    export NMDIR="${BATS_TEST_TMPDIR}/system-connections"
    export RHDIR="${BATS_TEST_TMPDIR}/network-scripts"
    export SUSEDIR="${BATS_TEST_TMPDIR}/sysconfig-network"
    export UBUDIR="${BATS_TEST_TMPDIR}/interfaces.d"
}

@test "an Ubuntu node with no interfaces.d is backed up without an error" {
    NIC_CFG_BACKEND=ubuntu run "$SCRIPT" backup
    [ "$status" -eq 0 ]
    [ -d "$BACKUP" ]
}

@test "an Ubuntu node with an interfaces.d has its files backed up" {
    mkdir -p "$UBUDIR"
    printf 'auto ens3\n' >"$UBUDIR/ens3"
    NIC_CFG_BACKEND=ubuntu run "$SCRIPT" backup
    [ "$status" -eq 0 ]
    [ -f "$BACKUP/ens3" ]
}

@test "a NetworkManager node with no keyfile directory is backed up without an error" {
    NIC_CFG_BACKEND=nm run "$SCRIPT" backup
    [ "$status" -eq 0 ]
    [ -d "$BACKUP" ]
}

@test "a Red Hat node with no network-scripts is backed up without an error" {
    NIC_CFG_BACKEND=rh run "$SCRIPT" backup
    [ "$status" -eq 0 ]
    [ -d "$BACKUP" ]
}

@test "a SUSE node with no sysconfig network directory is backed up without an error" {
    NIC_CFG_BACKEND=suse run "$SCRIPT" backup
    [ "$status" -eq 0 ]
    [ -d "$BACKUP" ]
}

@test "a backup that cannot create its own directory still fails" {
    export BACKUP="${BATS_TEST_TMPDIR}/not-a-dir/backupnet"
    printf 'x\n' >"${BATS_TEST_TMPDIR}/not-a-dir"
    NIC_CFG_BACKEND=ubuntu run "$SCRIPT" backup
    [ "$status" -ne 0 ]
}
