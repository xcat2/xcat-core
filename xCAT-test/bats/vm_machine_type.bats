#!/usr/bin/env bats
# vm_machine_type.sh sets machine:invalid, then a valid machine type, then clears it again.
# lsdef and chdef are shell functions that read and write vmothersetting of node cn1 in a file.

load 'helpers/shell_source'

setup()
{
    source "$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/vm_machine_type.sh')"
    VMOTHER="${BATS_TEST_TMPDIR}/vmothersetting"
    export VM_MACHINE_TYPE_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -m 0700 "$VM_MACHINE_TYPE_STATE_DIR"
    STATE="${VM_MACHINE_TYPE_STATE_DIR}/xcattest-cn1-vmothersetting"
    LSDEF_FAIL=0
    CHDEF_FAIL=0
    CHDEF_CALLS=0
}

# lsdef prints no line for an attribute without a value.
lsdef()
{
    if [ "$LSDEF_FAIL" -ne 0 ]; then
        echo "Error: [mn]: Could not find an object named '$1' of type 'node'." >&2
        return 1
    fi
    printf 'Object name: %s\n' "$1"
    if [ -s "$VMOTHER" ]; then
        printf '    vmothersetting=%s\n' "$(cat "$VMOTHER")"
    fi
}

chdef()
{
    [ "$1" = cn1 ] || return 1
    [ "$CHDEF_FAIL" -eq 0 ] || return 1
    case "$2" in
        vmothersetting=*) printf '%s' "${2#vmothersetting=}" >"$VMOTHER" ;;
        *) return 1 ;;
    esac
    CHDEF_CALLS=$((CHDEF_CALLS + 1))
}

set_vmother()
{
    printf '%s' "$1" >"$VMOTHER"
}

vmother()
{
    cat "$VMOTHER"
}

# assert_arch <arch> <machine> <original> -- the value after each step of the case.
assert_arch()
{
    local arch="$1" machine="$2" original="$3" sep=''
    [ -z "$original" ] || sep=';'
    CHDEF_CALLS=0

    set_vmother "$original"
    vm_machine_type_main invalid cn1
    [ "$(vmother)" = "${original}${sep}machine:invalid" ]

    vm_machine_type_main apply cn1 "$arch"
    [ "$(vmother)" = "${original}${sep}machine:$machine" ]

    vm_machine_type_main restore cn1 "$arch"
    [ "$(vmother)" = "$original" ]
    [ "$CHDEF_CALLS" -eq 3 ]
}

@test "ppc64le: the case sets and clears pseries-rhel7.6.0" {
    assert_arch ppc64le pseries-rhel7.6.0 ''
    assert_arch ppc64le pseries-rhel7.6.0 'cpumode:host-passthrough'
}

@test "x86_64: the case sets and clears pc" {
    assert_arch x86_64 pc ''
    assert_arch x86_64 pc 'cpumode:host-passthrough'
}

@test "riscv64: the case sets and clears virt" {
    assert_arch riscv64 virt ''
    assert_arch riscv64 virt 'cpumode:host-passthrough'
}

@test "aarch64: the case sets and clears virt" {
    assert_arch aarch64 virt ''
    assert_arch aarch64 virt 'cpumode:host-passthrough'
}

# assert_round_trip <arch> <original> -- the case ends with the exact value it started with.
assert_round_trip()
{
    local arch="$1" original="$2" machine

    set_vmother "$original"
    vm_machine_type_main invalid cn1
    # kvm.pm uses the last machine: field of vmothersetting.
    machine="$(vmother | tr ';' '\n' | grep '^machine:' | tail -n 1)"
    [ "$machine" = "machine:invalid" ]

    vm_machine_type_main apply cn1 "$arch"
    vm_machine_type_main restore cn1 "$arch"
    [ "$(vmother)" = "$original" ]
    [ -z "$(ls -A "$VM_MACHINE_TYPE_STATE_DIR")" ]
}

@test "round trip: no vmothersetting" {
    assert_round_trip x86_64 ''
}

@test "round trip: machine:invalid" {
    assert_round_trip x86_64 'machine:invalid'
}

@test "round trip: cpumode:host-passthrough" {
    assert_round_trip x86_64 'cpumode:host-passthrough'
}

@test "round trip: x86_64 with a versioned machine type" {
    assert_round_trip x86_64 'cpumode:host-passthrough;machine:pc-q35-9.2'
}

@test "round trip: riscv64 with a versioned machine type" {
    assert_round_trip riscv64 'machine:virt-9.2'
}

@test "round trip: riscv64 with a versioned machine type after another setting" {
    assert_round_trip riscv64 'cpumode:host-passthrough;machine:virt-9.2'
}

@test "round trip: several settings" {
    assert_round_trip ppc64le 'vcpupin:0-3;membind:0;devpassthrough:pci_0000_01_00_0,pci_0000_02_00_0;cpumode:host-model'
}

@test "apply keeps a machine type the node already names" {
    set_vmother 'cpumode:host-passthrough;machine:pc-q35-9.2'
    vm_machine_type_main invalid cn1
    vm_machine_type_main apply cn1 x86_64
    [ "$(vmother)" = 'cpumode:host-passthrough;machine:pc-q35-9.2' ]
}

@test "restore without a saved value fails and leaves vmothersetting alone" {
    set_vmother 'cpumode:host-passthrough;machine:pc'
    run vm_machine_type_main restore cn1 x86_64
    [ "$status" -ne 0 ]
    [[ "$output" == *"no saved vmothersetting for cn1"* ]]
    [ "$(vmother)" = 'cpumode:host-passthrough;machine:pc' ]
}

@test "apply fails for an architecture without a machine type" {
    set_vmother ''
    vm_machine_type_main invalid cn1
    run vm_machine_type_main apply cn1 s390x
    [ "$status" -ne 0 ]
    [[ "$output" == *"no machine type for arch 's390x'"* ]]
    [ "$(vmother)" = 'machine:invalid' ]
}

@test "invalid saves an empty vmothersetting that lsdef read" {
    set_vmother ''
    vm_machine_type_main invalid cn1
    [ -f "$STATE" ]
    [ ! -s "$STATE" ]
    [ "$(vmother)" = 'machine:invalid' ]
}

@test "invalid creates a private state directory" {
    rmdir "$VM_MACHINE_TYPE_STATE_DIR"
    vm_machine_type_main invalid cn1
    [ -d "$VM_MACHINE_TYPE_STATE_DIR" ]
    [ -z "$(find "$VM_MACHINE_TYPE_STATE_DIR" -maxdepth 0 -perm /077)" ]
}

@test "invalid fails without a snapshot or chdef when lsdef fails" {
    set_vmother 'cpumode:host-passthrough'
    LSDEF_FAIL=1
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot read vmothersetting of cn1"* ]]
    [ ! -e "$STATE" ]
    [ "$CHDEF_CALLS" -eq 0 ]
    [ "$(vmother)" = 'cpumode:host-passthrough' ]
}

@test "a second invalid is refused and keeps the first snapshot" {
    set_vmother 'cpumode:host-passthrough'
    vm_machine_type_main invalid cn1
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [[ "$output" == *"saved vmothersetting for cn1 already exists"* ]]
    [ "$(cat "$STATE")" = 'cpumode:host-passthrough' ]
    [ "$(vmother)" = 'cpumode:host-passthrough;machine:invalid' ]
    [ "$CHDEF_CALLS" -eq 1 ]

    vm_machine_type_main apply cn1 x86_64
    vm_machine_type_main restore cn1 x86_64
    [ "$(vmother)" = 'cpumode:host-passthrough' ]
}

@test "invalid refuses a snapshot left by an earlier run" {
    set_vmother 'cpumode:host-passthrough'
    printf '%s' 'machine:stale' >"$STATE"
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [[ "$output" == *"saved vmothersetting for cn1 already exists"* ]]
    [ "$(cat "$STATE")" = 'machine:stale' ]
    [ "$(vmother)" = 'cpumode:host-passthrough' ]
    [ "$CHDEF_CALLS" -eq 0 ]
}

@test "invalid refuses a symbolic link as the state file" {
    set_vmother 'cpumode:host-passthrough'
    ln -s "${BATS_TEST_TMPDIR}/target" "$STATE"
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/target" ]
    [ "$(vmother)" = 'cpumode:host-passthrough' ]
    [ "$CHDEF_CALLS" -eq 0 ]
}

@test "restore refuses a symbolic link as the state file" {
    set_vmother 'cpumode:host-passthrough;machine:pc'
    printf '%s' 'machine:other' >"${BATS_TEST_TMPDIR}/target"
    ln -s "${BATS_TEST_TMPDIR}/target" "$STATE"
    run vm_machine_type_main restore cn1 x86_64
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a regular file"* ]]
    [ "$(vmother)" = 'cpumode:host-passthrough;machine:pc' ]
    [ "$CHDEF_CALLS" -eq 0 ]
}

@test "invalid refuses a symbolic link as the state directory" {
    set_vmother 'cpumode:host-passthrough'
    rmdir "$VM_MACHINE_TYPE_STATE_DIR"
    mkdir -m 0700 "${BATS_TEST_TMPDIR}/real"
    ln -s "${BATS_TEST_TMPDIR}/real" "$VM_MACHINE_TYPE_STATE_DIR"
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a private directory"* ]]
    [ -z "$(ls -A "${BATS_TEST_TMPDIR}/real")" ]
    [ "$(vmother)" = 'cpumode:host-passthrough' ]
    [ "$CHDEF_CALLS" -eq 0 ]
}

@test "invalid refuses a state directory that other users can write" {
    set_vmother 'cpumode:host-passthrough'
    chmod 0777 "$VM_MACHINE_TYPE_STATE_DIR"
    run vm_machine_type_main invalid cn1
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not a private directory"* ]]
    [ -z "$(ls -A "$VM_MACHINE_TYPE_STATE_DIR")" ]
    [ "$CHDEF_CALLS" -eq 0 ]
}

@test "restore keeps the snapshot when chdef fails" {
    set_vmother 'cpumode:host-passthrough'
    vm_machine_type_main invalid cn1
    CHDEF_FAIL=1
    run vm_machine_type_main restore cn1 x86_64
    [ "$status" -ne 0 ]
    [ "$(cat "$STATE")" = 'cpumode:host-passthrough' ]
    [ "$(vmother)" = 'cpumode:host-passthrough;machine:invalid' ]
}
