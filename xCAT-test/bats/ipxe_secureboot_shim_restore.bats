#!/usr/bin/env bats
#
# Drive ipxe_secureboot_shim.sh, the helper of the nodeset_ipxe_secureboot_shim case. The case
# calls nodeset to reconfigure one node for installation, reads the UEFI script, and puts the
# nodeset state back. A restoration that fails leaves the node configured for installation, and
# the next case on that node measures the state this one left. So the helper has to report a
# failed restoration instead of its own result.
#
# lsdef, nodeset and chdef are stubbed, and every call is recorded in a log the tests read.

load 'helpers/shell_source'

NODE=cn01
OS=alma9.8

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/nodeset/ipxe_secureboot_shim.sh')"
    BIN="${BATS_TEST_TMPDIR}/bin"
    TFTPDIR="${BATS_TEST_TMPDIR}/tftpboot"
    INSTALLDIR="${BATS_TEST_TMPDIR}/install"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "$BIN" "$TFTPDIR/xcat/ipxe/nodes" "$INSTALLDIR/$OS/x86_64/EFI/BOOT"
    : >"$CALLS"
    # The shim the boot script names. The helper fails when the file is absent.
    printf 'shim\n' >"$INSTALLDIR/$OS/x86_64/EFI/BOOT/BOOTX64.EFI"

    # The nodeset state the helper has to put back, and the provmethod it finds. An empty
    # provmethod is what sends the helper through chdef on the way out.
    export STUB_BEFORE=boot
    export STUB_PROVMETHOD=
    export STUB_NODESET_RESTORE_RC=0
    export STUB_CHDEF_RC=0
    export STUB_NO_OSIMAGE=
    export STUB_UEFI="$TFTPDIR/xcat/ipxe/nodes/${NODE}.uefi"
    export STUB_SHIM_LINE="shim http://\${next-server}/install/$OS/x86_64/EFI/BOOT/BOOTX64.EFI"
    export STUB_CALLS="$CALLS"
    export STUB_TFTPDIR="$TFTPDIR"
    export STUB_INSTALLDIR="$INSTALLDIR"
    export STUB_OS="$OS"

    cat >"$BIN/lsdef" <<'STUB'
#!/bin/bash
echo "lsdef $*" >>"$STUB_CALLS"
type=; obj=; attr=
while [ $# -gt 0 ]; do
    case "$1" in
        -t) type="$2"; shift 2 ;;
        -o) obj="$2"; shift 2 ;;
        -i) attr="$2"; shift 2 ;;
        *) shift ;;
    esac
done
case "$type/$attr" in
    site/tftpdir)    echo "    tftpdir=$STUB_TFTPDIR" ;;
    site/installdir) echo "    installdir=$STUB_INSTALLDIR" ;;
    node/netboot)    echo "    netboot=ipxe" ;;
    node/arch)       echo "    arch=x86_64" ;;
    node/os)         echo "    os=$STUB_OS" ;;
    node/provmethod) [ -n "$STUB_PROVMETHOD" ] && echo "    provmethod=$STUB_PROVMETHOD" ;;
    osimage/)        [ -n "$STUB_NO_OSIMAGE" ] && exit 1; exit 0 ;;
    *) echo "unexpected lsdef $type $obj $attr" >&2; exit 1 ;;
esac
exit 0
STUB

    # nodeset stat reports the state; osimage= writes the UEFI script; any destiny name is the
    # restoration call, and its exit status is what these tests drive.
    cat >"$BIN/nodeset" <<'STUB'
#!/bin/bash
echo "nodeset $*" >>"$STUB_CALLS"
case "$2" in
    stat)
        echo "$1: $STUB_BEFORE"
        ;;
    osimage=*)
        {
            echo '#!gpxe'
            echo 'imgfetch -n kernel http://${next-server}/tftpboot/xcat/osimage/vmlinuz'
            echo 'imgload kernel'
            echo "$STUB_SHIM_LINE"
            echo 'imgargs kernel quiet'
            echo 'imgexec kernel'
        } >"$STUB_UEFI"
        ;;
    *)
        exit "$STUB_NODESET_RESTORE_RC"
        ;;
esac
exit 0
STUB

    cat >"$BIN/chdef" <<'STUB'
#!/bin/bash
echo "chdef $*" >>"$STUB_CALLS"
exit "$STUB_CHDEF_RC"
STUB

    chmod 0755 "$BIN"/*
    export PATH="$BIN:$PATH"
}

@test "a node whose state goes back reports the shim it found" {
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    grep -q "^nodeset $NODE boot$" "$CALLS"
    grep -q "^chdef -t node -o $NODE provmethod=$" "$CALLS"
}

@test "a nodeset that cannot put the state back fails the case" {
    STUB_NODESET_RESTORE_RC=1
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *IPXE_SHIM_FAIL* ]]
    grep -q "^nodeset $NODE boot$" "$CALLS"
}

@test "a chdef that cannot clear the provmethod fails the case" {
    STUB_CHDEF_RC=1
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *IPXE_SHIM_FAIL* ]]
    grep -q "^chdef -t node -o $NODE provmethod=$" "$CALLS"
}

# A control: the helper already restores the state when its own assertion fails. It holds the
# restoration on the exit path down, so a later exit cannot skip it.
@test "a script without a shim after imgload still puts the state back" {
    STUB_SHIM_LINE='imgargs kernel quiet'
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" == *IPXE_SHIM_FAIL* ]]
    grep -q "^nodeset $NODE boot$" "$CALLS"
}

# A skip above the nodeset call changed nothing, so the helper must not call nodeset to put a
# state back it never left. An osimage that is not defined is such a skip.
@test "a node the helper skips calls no nodeset and no chdef" {
    STUB_NO_OSIMAGE=1
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_SKIPPED* ]]
    refute_grep -q "^nodeset $NODE boot$" "$CALLS"
    refute_grep -q "^chdef " "$CALLS"
}
