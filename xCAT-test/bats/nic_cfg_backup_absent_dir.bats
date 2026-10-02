#!/usr/bin/env bats
#
# nic_cfg.sh backup must succeed on a node that has no persistent network configuration yet.
#
# Regression: the backup arm ended in a cp over the backend's config directory, so the script
# exited with that cp's status. A node that has just netbooted has no
# /etc/network/interfaces.d, so the cp failed and the caller read "nothing to back up" as a
# failure. confignetwork_static_installnic failed on its third command for that reason, while
# the identical call seven seconds later, after confignetwork had created the directory,
# returned 0.
#
# The backend and every directory come from the environment, so nothing on the host is read or
# written.

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
