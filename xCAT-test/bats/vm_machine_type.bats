#!/usr/bin/env bats
# vm_machine_type.sh sets machine:invalid, then a valid machine type, then clears it again.
# lsdef and chdef are shell functions that read and write vmothersetting of node cn1 in a file.

load 'helpers/shell_source'

setup()
{
    source "$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/vm_machine_type.sh')"
    VMOTHER="${BATS_TEST_TMPDIR}/vmothersetting"
    export VM_MACHINE_TYPE_STATE_DIR="${BATS_TEST_TMPDIR}/state"
    mkdir -p "$VM_MACHINE_TYPE_STATE_DIR"
}

# lsdef prints no line for an attribute without a value.
lsdef()
{
    printf 'Object name: %s\n' "$1"
    if [ -s "$VMOTHER" ]; then
        printf '    vmothersetting=%s\n' "$(cat "$VMOTHER")"
    fi
}

chdef()
{
    [ "$1" = cn1 ] || return 1
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
