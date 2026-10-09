#!/usr/bin/env bats
#
# Drive ipxe_secureboot_shim.sh, the helper of the nodeset_ipxe_secureboot_shim case. The case
# calls nodeset to reconfigure one node for installation, reads the UEFI script, and puts the
# nodeset state back. A restoration that fails leaves the node configured for installation, and
# the next case on that node measures the state this one left. So the helper has to report a
# failed restoration instead of its own result.
#
# lsdef, nodeset and chdef are stubbed, and every call is recorded in a log the tests read. A
# stub can also be told to fail: STUB_STAT_RC fails "nodeset stat", and STUB_LSDEF_FAIL_ATTR
# fails the lsdef of one attribute. Both failures print nothing on stdout, which is what an
# attribute that is unset prints too.

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
    export STUB_PROFILE=compute
    export STUB_STAT_RC=0
    export STUB_LSDEF_FAIL_ATTR=
    export STUB_NODESET_RESTORE_RC=0
    export STUB_CHDEF_RC=0
    # Which chdef netboot= call to fail, counted from 1. The helper sets the method and later
    # puts it back, so one return code for both cannot say which call failed.
    export STUB_CHDEF_NETBOOT_FAIL_NTH=0
    # The netboot the node is declared with. Four of the six confs that carry this case declare
    # their compute node netboot=xnba, so this is not a hypothetical value.
    export STUB_NETBOOT=ipxe
    export STUB_ARCH=x86_64
    export STUB_NO_OSIMAGE=
    export STUB_UEFI="$TFTPDIR/xcat/ipxe/nodes/${NODE}.uefi"
    export STUB_SHIM_LINE="shim http://\${next-server}/install/$OS/x86_64/EFI/BOOT/BOOTX64.EFI"
    export STUB_CALLS="$CALLS"
    export STUB_NETBOOT_COUNT="$BATS_TEST_TMPDIR/netboot-count"
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
# A failed lookup prints nothing and exits non-zero. An attribute that is unset prints nothing
# and exits zero, so only the exit status tells the two apart.
if [ -n "$STUB_LSDEF_FAIL_ATTR" ] && [ "$attr" = "$STUB_LSDEF_FAIL_ATTR" ]; then
    echo "Error: could not read $attr" >&2
    exit 1
fi
case "$type/$attr" in
    site/tftpdir)    echo "    tftpdir=$STUB_TFTPDIR" ;;
    site/installdir) echo "    installdir=$STUB_INSTALLDIR" ;;
    node/netboot)    echo "    netboot=$STUB_NETBOOT" ;;
    node/arch)       echo "    arch=$STUB_ARCH" ;;
    node/os)         echo "    os=$STUB_OS" ;;
    node/provmethod) [ -n "$STUB_PROVMETHOD" ] && echo "    provmethod=$STUB_PROVMETHOD" ;;
    node/profile)    [ -n "$STUB_PROFILE" ] && echo "    profile=$STUB_PROFILE" ;;
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
        [ "$STUB_STAT_RC" = 0 ] || { echo "Error: cannot reach the server" >&2; exit "$STUB_STAT_RC"; }
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
    *netboot=*)
        n=$(( $(cat "$STUB_NETBOOT_COUNT" 2>/dev/null || echo 0) + 1 ))
        echo "$n" >"$STUB_NETBOOT_COUNT"
        [ "$n" = "$STUB_CHDEF_NETBOOT_FAIL_NTH" ] && exit 1
        exit 0
        ;;
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
    grep -q "^chdef -t node -o $NODE provmethod= profile=compute$" "$CALLS"
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
    grep -q "^chdef -t node -o $NODE provmethod= profile=compute$" "$CALLS"
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
    # Fail the SECOND netboot chdef, which is the restoring one. Failing both cannot tell a
    # broken restoration from a forward chdef that never ran.
    STUB_CHDEF_NETBOOT_FAIL_NTH=2
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    # The forward chdef must have succeeded, or this measures the wrong call.
    grep -q "^chdef -t node -o $NODE netboot=ipxe$" "$CALLS"
    # Only the restoring branch prints this; the forward one does not.
    [[ "$output" == *"keeps the netboot method this case set"* ]]
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


# nodeset stat reports chain.currstate verbatim, and a state can carry an argument:
# "runcmd=bmcsetup" is one state, not the state "runcmd". The helper matched ${before%% *}
# against four names, so a node in any other state kept the installation this case configured
# and the case still printed IPXE_SHIM_OK.
@test "a runcmd state goes back with its command argument" {
    STUB_BEFORE='runcmd=bmcsetup'
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    grep -q "^nodeset $NODE runcmd=bmcsetup$" "$CALLS"
}

# The saved image is not the image the helper sets, or the assertion matches the helper's own
# forward call and cannot fail.
@test "an osimage state goes back with its image name" {
    STUB_BEFORE="osimage=$OS-x86_64-netboot-compute"
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    grep -q "^nodeset $NODE osimage=$OS-x86_64-netboot-compute$" "$CALLS"
}

# install, netboot and statelite are deprecated: destiny.pm answers "The options install,
# netboot and statelite have been deprecated" and sets errorabort, so replaying one fails and
# leaves the node configured for installation. The helper cannot put such a state back, so it
# must refuse while the node is still untouched.
@test "a saved state the helper cannot replay stops it before the first mutation" {
    STUB_BEFORE=install
    STUB_NETBOOT=xnba
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *"state [install]"* ]]
    refute_grep -q "^chdef " "$CALLS"
    refute_grep -q "^nodeset $NODE osimage" "$CALLS"
}

# A pipeline hides the exit status of its first command, so "nodeset stat | sed | head" reported
# success with an empty state. The helper then read the node as stateless and restored nothing.
@test "a nodeset stat that fails stops the helper before the first mutation" {
    STUB_STAT_RC=1
    STUB_NETBOOT=xnba
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *"nodeset $NODE stat returned non-zero"* ]]
    refute_grep -q "^chdef " "$CALLS"
    refute_grep -q "^nodeset $NODE osimage" "$CALLS"
}

# lsdef prints nothing for an attribute that is unset, so a failed lookup and an unset attribute
# were the same empty string. The helper clears the provmethod it believes was unset, so a
# failed lookup made it delete the provmethod the node really had.
@test "a provmethod lookup that fails does not clear the provmethod" {
    STUB_LSDEF_FAIL_ATTR=provmethod
    STUB_PROVMETHOD=alma9.8-x86_64-install-compute
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *"-i provmethod"* ]]
    refute_grep -q "^chdef " "$CALLS"
    refute_grep -q "^nodeset $NODE osimage" "$CALLS"
}

# The same read, the same damage: a netboot method read as empty is put back as empty, which
# clears the method the cluster boots the node with.
@test "a netboot lookup that fails does not change the netboot method" {
    STUB_LSDEF_FAIL_ATTR=netboot
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" != *IPXE_SHIM_OK* ]]
    [[ "$output" == *"-i netboot"* ]]
    refute_grep -q "^chdef " "$CALLS"
    refute_grep -q "^nodeset $NODE osimage" "$CALLS"
}

# A control for the two above: an attribute that is readable and unset is not a failed lookup,
# and the helper still runs. Without this the tests above are satisfied by a helper that refuses
# every empty attribute.
@test "a provmethod that is unset but readable is not a failed lookup" {
    STUB_PROVMETHOD=
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    grep -q "^nodeset $NODE osimage=$OS-x86_64-install-compute$" "$CALLS"
}

# setdestiny writes nodetype.provmethod, profile, os and arch from the osimage row it resolved
# (destiny.pm, "my $updateattribs"). On the path where the helper names its own
# <os>-<arch>-install-compute image, os and arch come back as the node's own values by
# construction of that name, and profile does not: it becomes the row's profile.
@test "the profile that nodeset osimage overwrites goes back too" {
    STUB_PROVMETHOD=
    STUB_PROFILE=service
    run "$SCRIPT" "$NODE"
    [ "$status" -eq 0 ]
    [[ "$output" == *IPXE_SHIM_OK* ]]
    grep -q "^chdef -t node -o $NODE provmethod= profile=service$" "$CALLS"
}

# An arch that cannot be read is not an arch that is wrong, and the message has to say which.
@test "an arch lookup that fails is reported as a failed lookup" {
    STUB_LSDEF_FAIL_ATTR=arch
    run "$SCRIPT" "$NODE"
    [ "$status" -ne 0 ]
    [[ "$output" == *"-i arch"* ]]
    [[ "$output" != *"only x86_64 has a UEFI shim"* ]]
}
