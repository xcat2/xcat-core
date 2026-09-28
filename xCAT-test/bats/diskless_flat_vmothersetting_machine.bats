#!/usr/bin/env bats
#
# reg_linux_diskless_installation_flat corrupts the KVM machine type of the compute node, checks
# that the node fails to boot, and then restores it. The restore reads a machine type from a
# ladder that names ppc64 and x86_64 only, so on any other architecture it writes an empty
# vmothersetting and the check after it fails.
#
# The two commands are lifted out of the case file and RUN, with lsdef and chdef shadowed, so
# the assertions read the value the case would write. The extraction fails the test when it
# stops matching, so a rewrite fails loudly instead of covering nothing.

load 'helpers/shell_source'

setup()
{
    CASE="$(repo_path 'xCAT-test/autotest/testcase/installation/reg_linux_diskless_installation_flat')"
    [ -r "$CASE" ] || skip "$CASE is required"
    export CASE
}

# The command that restores the machine type, and the one that removes it again afterwards.
restore_command()
{
    extract_first_matching_line "$CASE" \
        '^cmd:.*str2="machine:invalid".*chdef [$][$]CN vmothersetting=[$]str5'
}

remove_command()
{
    extract_first_matching_line "$CASE" \
        '^cmd:.*str2=";".*~ "ppc64".*chdef [$][$]CN vmothersetting='
}

# Render one command the way xcattest does, then run it with lsdef and chdef shadowed. bash
# resolves a function ahead of PATH, so the case's own backticks read the stub.
#
# Sets OUT to everything the command printed and WRITTEN to the value it gave chdef.
run_case_command()
{
    local cmd="$1" arch="$2" lsdef_value="$3"

    cmd="${cmd#cmd:}"
    cmd="${cmd//__GETNODEATTR(\$\$CN,arch)__/$arch}"
    cmd="${cmd//__GETNODEATTR(\$\$CN,mgt)__/kvm}"
    cmd="${cmd//\$\$CN/cn1}"

    OUT="$(bash -c "lsdef() { echo '    vmothersetting=$lsdef_value'; }
chdef() { echo \"CHDEF:[\$*]\"; }
$cmd" 2>&1)" || true
    # The brackets keep an empty value apart from no call at all: the cleanup is meant to write
    # an empty vmothersetting, and a command that never reaches chdef must not read as that.
    CHDEF_CALLS="$(grep -c '^CHDEF:' <<<"$OUT" || true)"
    WRITTEN="$(sed -n 's/^CHDEF:\[cn1 vmothersetting=\(.*\)\]$/\1/p' <<<"$OUT")"
}

# The machine type each architecture must end up with. riscv64 guests run the qemu "virt"
# machine; kvm.pm sets it in guest_arch_profile.
#
# The restore writes the machine type; the cleanup after it takes the same machine type away
# again and leaves every other setting. Both read the same ladder, so both are checked against
# the same value.
assert_arch()
{
    local arch="$1" machine="$2" restore remove

    restore="$(restore_command)"
    remove="$(remove_command)"

    # The node carries the corrupt value only.
    run_case_command "$restore" "$arch" 'machine:invalid'
    [ "$CHDEF_CALLS" -eq 1 ]
    [ "$WRITTEN" = "machine:$machine" ]

    # The node carries a setting of its own beside the corrupt value.
    run_case_command "$restore" "$arch" 'cpumode:host-passthrough;machine:invalid'
    [ "$CHDEF_CALLS" -eq 1 ]
    [ "$WRITTEN" = "cpumode:host-passthrough;machine:$machine" ]

    # The cleanup, with nothing but the machine type to remove.
    run_case_command "$remove" "$arch" "machine:$machine"
    [ "$(grep -c 'unary operator expected' <<<"$OUT")" -eq 0 ]
    [ "$CHDEF_CALLS" -eq 1 ]
    [ "$WRITTEN" = "" ]

    # The cleanup, with a setting of its own that must survive it.
    run_case_command "$remove" "$arch" "cpumode:host-passthrough;machine:$machine"
    [ "$(grep -c 'unary operator expected' <<<"$OUT")" -eq 0 ]
    [ "$CHDEF_CALLS" -eq 1 ]
    [ "$WRITTEN" = "cpumode:host-passthrough" ]
}

@test "ppc64le: the restore writes the machine type and the cleanup takes it away" {
    assert_arch ppc64le pseries-rhel7.6.0
}

@test "x86_64: the restore writes the machine type and the cleanup takes it away" {
    assert_arch x86_64 pc
}

@test "riscv64: the restore writes the machine type and the cleanup takes it away" {
    assert_arch riscv64 virt
}
