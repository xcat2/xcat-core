#!/bin/bash
# vm_machine_type.sh - set and clear the KVM machine type in vmothersetting of a node.
#
# Usage:
#   vm_machine_type.sh invalid <node>          save vmothersetting, then add machine:invalid
#   vm_machine_type.sh apply <node> <arch>     write the saved value with a valid machine type
#   vm_machine_type.sh restore <node> [<arch>] write the saved value back and delete it
#
# The saved value is in $VM_MACHINE_TYPE_STATE_DIR (default /tmp), one file per node.

vm_machine_type_state()
{
    printf '%s/xcattest-%s-vmothersetting\n' "${VM_MACHINE_TYPE_STATE_DIR:-/tmp}" "$1"
}

vm_machine_type_for_arch()
{
    case "$1" in
        ppc64*)  echo 'machine:pseries-rhel7.6.0' ;;
        x86_64)  echo 'machine:pc' ;;
        riscv64) echo 'machine:virt' ;;
        aarch64) echo 'machine:virt' ;;
        *)       return 1 ;;
    esac
}

vm_machine_type_get()
{
    lsdef "$1" -i vmothersetting | sed -n 's/^[[:space:]]*vmothersetting=//p'
}

vm_machine_type_saved()
{
    local state
    state="$(vm_machine_type_state "$1")"
    if [ ! -f "$state" ]; then
        echo "vm_machine_type.sh: no saved vmothersetting for $1 in $state" >&2
        return 1
    fi
    cat "$state"
}

# join <first> <second> -- join two vmothersetting values with ";".
vm_machine_type_join()
{
    if [ -z "$1" ]; then
        printf '%s\n' "$2"
    else
        printf '%s;%s\n' "$1" "$2"
    fi
}

vm_machine_type_invalid()
{
    local node="$1" original
    original="$(vm_machine_type_get "$node")"
    printf '%s' "$original" >"$(vm_machine_type_state "$node")" || return 1
    # kvm.pm uses the last machine: setting.
    chdef "$node" "vmothersetting=$(vm_machine_type_join "$original" 'machine:invalid')"
}

vm_machine_type_apply()
{
    local node="$1" arch="$2" original machine
    original="$(vm_machine_type_saved "$node")" || return 1
    # A machine type the node already names stays in place.
    if [[ ";$original" == *";machine:"* ]]; then
        chdef "$node" "vmothersetting=$original"
        return
    fi
    if ! machine="$(vm_machine_type_for_arch "$arch")"; then
        echo "vm_machine_type.sh: no machine type for arch '$arch'" >&2
        return 1
    fi
    chdef "$node" "vmothersetting=$(vm_machine_type_join "$original" "$machine")"
}

vm_machine_type_restore()
{
    local node="$1" original
    original="$(vm_machine_type_saved "$node")" || return 1
    # An empty value makes chdef delete the attribute.
    chdef "$node" "vmothersetting=$original" || return 1
    rm -f "$(vm_machine_type_state "$node")"
}

vm_machine_type_main()
{
    local action="$1"
    shift
    case "$action" in
        invalid) vm_machine_type_invalid "$@" ;;
        apply)   vm_machine_type_apply "$@" ;;
        restore) vm_machine_type_restore "$@" ;;
        *)
            echo "usage: vm_machine_type.sh {invalid <node>|apply <node> <arch>|restore <node> [<arch>]}" >&2
            return 2
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    vm_machine_type_main "$@"
fi
