#!/usr/bin/env bats
#
# Drive selinux_context.sh, the helper the genesis_kernel_selinux_context case runs on a
# management node. It needs SELinux, mknb and the xCAT site table, so shadow all three and
# point XCATROOT at a scratch image root.

load 'helpers/shell_source'

setup()
{
    HELPER="$(repo_path 'xCAT-test/autotest/testcase/genesis/selinux_context.sh')"
    [ -r "$HELPER" ] || skip "$HELPER is required"
    BIN="${BATS_TEST_TMPDIR}/bin"
    TFTPDIR="${BATS_TEST_TMPDIR}/tftpboot"
    IMAGE_ROOT="${BATS_TEST_TMPDIR}/xcatroot"
    mkdir -p "$BIN" "$TFTPDIR/xcat" "$IMAGE_ROOT"
    export HELPER BIN TFTPDIR IMAGE_ROOT
}

stub()
{
    printf '#!/bin/sh\n%s\n' "$2" >"$BIN/$1"
    chmod 0755 "$BIN/$1"
}

# The commands the helper calls on an SELinux management node. mknb stages a kernel named for
# the architecture it resolved, which is not always the architecture it was asked for.
stub_node()
{
    local staged_arch="$1" restorecon_body="${2:-exit 0}"
    stub lsdef "echo '    tftpdir=$TFTPDIR'"
    stub selinuxenabled 'exit 0'
    stub getenforce 'echo Enforcing'
    stub mknb "echo kernel > '$TFTPDIR/xcat/genesis.kernel.$staged_arch'"
    stub restorecon "$restorecon_body"
}

# The image root mknb reads to choose between an OpenEmbedded export and the legacy tree.
install_genesis()
{
    local kind="$1" arch="$2"
    mkdir -p "$IMAGE_ROOT/share/xcat/netboot/$kind/$arch"
}

run_helper()
{
    PATH="$BIN:$PATH" XCATROOT="$IMAGE_ROOT" bash "$HELPER" "$@" 2>&1
}

@test "a verification command that fails without output is not a pass" {
    install_genesis genesis x86_64
    # restorecon can fail without naming a file: no policy loaded, or a path it cannot read.
    stub_node x86_64 'exit 3'

    run run_helper x86_64
    [ "$status" -ne 0 ]
    [[ "$output" == *GENESIS_SELINUX_FAIL* ]]
    [[ "$output" != *GENESIS_SELINUX_OK* ]]
    [[ "$output" == *3* ]]
}

@test "a legacy POWER node measures the kernel mknb staged" {
    # Only xCAT-genesis-openembedded-ppc64le creates the OpenEmbedded directory, and the
    # ppc64le genesis-legacy cells do not enable the repository that carries it. mknb then
    # uses share/xcat/netboot/genesis/ppc64 and writes genesis.kernel.ppc64.
    install_genesis genesis ppc64
    stub_node ppc64

    run run_helper ppc64le
    [ "$status" -eq 0 ]
    [[ "$output" == *GENESIS_SELINUX_OK* ]]
    [[ "$output" == *genesis.kernel.ppc64* ]]
    [[ "$output" != *genesis.kernel.ppc64le* ]]
}

@test "an OpenEmbedded POWER node keeps the exact architecture" {
    install_genesis genesis-openembedded ppc64le
    install_genesis genesis ppc64
    stub_node ppc64le

    run run_helper ppc64le
    [ "$status" -eq 0 ]
    [[ "$output" == *GENESIS_SELINUX_OK* ]]
    [[ "$output" == *genesis.kernel.ppc64le* ]]
}

@test "a kernel staged under another name fails and names both" {
    install_genesis genesis ppc64
    stub_node ppc64le

    run run_helper ppc64le
    [ "$status" -ne 0 ]
    [[ "$output" == *GENESIS_SELINUX_FAIL* ]]
    [[ "$output" == *genesis.kernel.ppc64* ]]
    [[ "$output" == *genesis.kernel.ppc64le* ]]
}
