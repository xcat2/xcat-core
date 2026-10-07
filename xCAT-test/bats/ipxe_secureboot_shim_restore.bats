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
    export STUB_CHDEF_NETBOOT_RC=0
    # The netboot the node is declared with. Four of the six confs that carry this case declare
    # their compute node netboot=xnba, so this is not a hypothetical value.
    export STUB_NETBOOT=ipxe
    export STUB_ARCH=x86_64
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
    node/netboot)    echo "    netboot=$STUB_NETBOOT" ;;
    node/arch)       echo "    arch=$STUB_ARCH" ;;
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
case "$*" in
    *netboot=*) exit "$STUB_CHDEF_NETBOOT_RC" ;;
esac
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

# An exit above the nodeset call changed nothing, so the helper must not call nodeset to put a
# state back it never left.
@test "a node with no osimage to name fails and calls no nodeset and no chdef" {
    STUB_NO_OSIMAGE=1
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" == *IPXE_SHIM_FAIL* ]]
    refute_grep -q "^nodeset $NODE boot$" "$CALLS"
    refute_grep -q "^chdef " "$CALLS"
}

# The case asserted output =~ IPXE_SHIM_(OK|SKIPPED), so a node the helper skipped PASSED the
# case. Four of the six confs that carry this case declare netboot=xnba on their compute node,
# so four cells passed it without reading a boot script at all. The helper now sets the netboot
# method it needs, measures, and puts the method back.
@test "a node declared netboot=xnba is measured, not skipped" {
    STUB_NETBOOT=xnba
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    [[ "$output" != *IPXE_SHIM_SKIPPED* ]]
    grep -q "^chdef -t node -o $NODE netboot=ipxe$" "$CALLS"
    grep -q "^chdef -t node -o $NODE netboot=xnba$" "$CALLS"
}

# The netboot method goes back before the restoring nodeset, or that nodeset writes the boot
# files of the wrong method.
@test "the netboot method goes back before the nodeset that restores the state" {
    STUB_NETBOOT=xnba
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    back=$(grep -n "^chdef -t node -o $NODE netboot=xnba$" "$CALLS" | cut -d: -f1)
    reset=$(grep -n "^nodeset $NODE boot$" "$CALLS" | cut -d: -f1)
    [ -n "$back" ] && [ -n "$reset" ] && [ "$back" -lt "$reset" ]
}

# A netboot method left as the case set it makes the next case on that node boot the wrong way,
# which is the same defect the provmethod and nodeset restorations already report.
@test "a netboot method that cannot be put back fails the case" {
    STUB_NETBOOT=xnba
    STUB_CHDEF_NETBOOT_RC=1
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *IPXE_SHIM_FAIL* ]]
}

# The case file now requires the OK token, so an exit 0 without it is a pass the run cannot
# tell from a measurement. Nothing the helper does may produce one.
@test "the helper never exits 0 without reporting IPXE_SHIM_OK" {
    for arch in x86_64 ppc64le; do
        for netboot in ipxe xnba; do
            for noimage in "" 1; do
                : >"$CALLS"
                STUB_ARCH=$arch STUB_NETBOOT=$netboot STUB_NO_OSIMAGE=$noimage \
                    run "$SCRIPT" "$NODE"
                if [ "$status" -eq 0 ] && [[ "$output" != *IPXE_SHIM_OK* ]]; then
                    echo "exit 0 with no OK: arch=$arch netboot=$netboot noimage=$noimage" >&2
                    echo "$output" >&2
                    return 1
                fi
            done
        done
    done
}
