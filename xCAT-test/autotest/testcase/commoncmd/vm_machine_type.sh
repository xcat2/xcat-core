#!/bin/bash
# vm_machine_type.sh - set and clear the KVM machine type in vmothersetting of a node.
#
# Usage:
#   vm_machine_type.sh invalid <node>          save vmothersetting, then add machine:invalid
#   vm_machine_type.sh apply <node> <arch>     write the saved value with a valid machine type
#   vm_machine_type.sh restore <node> [<arch>] write the saved value back and delete it
#
# The saved value is in $VM_MACHINE_TYPE_STATE_DIR, one file per node. The
# default directory is /tmp/xcattest-vmothersetting.<uid>.

vm_machine_type_dir()
{
    printf '%s\n' "${VM_MACHINE_TYPE_STATE_DIR:-/tmp/xcattest-vmothersetting.$(id -u)}"
}

vm_machine_type_state()
{
    printf '%s/xcattest-%s-vmothersetting\n' "$(vm_machine_type_dir)" "$1"
}

# private_dir -- create the state directory, or accept it only when it is a
# directory that the current user owns and nobody else can open.
vm_machine_type_private_dir()
{
    local dir
    dir="$(vm_machine_type_dir)"
    [ -e "$dir" ] || [ -L "$dir" ] || mkdir -m 0700 "$dir" 2>/dev/null
    if [ -L "$dir" ] || [ ! -d "$dir" ] || [ ! -O "$dir" ] ||
        [ -n "$(find "$dir" -maxdepth 0 -perm /077)" ]; then
        echo "vm_machine_type.sh: $dir is not a private directory of $(id -un)" >&2
        return 1
    fi
}

# alias <arch> [<vmothersetting>] -- the machine name qemu keeps pointed at the newest machine
# of a family. An x86_64 node that asks for a UEFI firmware takes q35: every x86_64 OVMF
# descriptor targets pc-q35-*, and libvirt refuses firmware efi on i440fx.
vm_machine_type_alias()
{
    case "$1" in
        ppc64*)  echo 'pseries' ;;
        x86_64)
            case ";${2-}" in
                *';firmware:efi'*) echo 'q35' ;;
                *)                 echo 'pc' ;;
            esac
            ;;
        riscv64) echo 'virt' ;;
        aarch64) echo 'virt' ;;
        *)       return 1 ;;
    esac
}

# libvirt and qemu call the ppc64le guest architecture ppc64. A node on an
# Ubuntu cell names it ppc64el.
vm_machine_type_libvirt_arch()
{
    case "$1" in
        ppc64*)  echo 'ppc64' ;;
        x86_64)  echo 'x86_64' ;;
        riscv64) echo 'riscv64' ;;
        aarch64) echo 'aarch64' ;;
        *)       return 1 ;;
    esac
}

# virsh on <host>, or here when <host> is empty. kvm.pm reaches the vmhost over
# qemu+ssh://root@<host>/system, so root can ssh there from this node.
vm_machine_type_virsh()
{
    local host="$1"
    shift
    if [ -n "$host" ]; then
        ssh -o BatchMode=yes -o ConnectTimeout=10 -n "$host" virsh "$@"
    else
        virsh "$@"
    fi
}

# supported <host> <arch> <machine> -- whether libvirt on <host> accepts <machine>.
vm_machine_type_supported()
{
    vm_machine_type_virsh "$1" domcapabilities --arch "$2" --machine "$3" >/dev/null 2>&1
}

# default <host> <arch> -- the machine type libvirt on <host> uses for <arch>.
vm_machine_type_default()
{
    vm_machine_type_virsh "$1" domcapabilities --arch "$2" 2>/dev/null |
        sed -n 's|.*<machine>\(.*\)</machine>.*|\1|p' | head -n 1
}

# for_arch <arch> [<vmhost>] [<vmothersetting>] -- the machine type to write, as
# "machine:<name>".
#
# The vmhost is what refuses the domain, so its libvirt picks the name: the plain
# alias when that libvirt accepts it, its own default when it does not, and the
# alias again when the vmhost cannot be asked. A versioned name does not survive
# a host upgrade -- no qemu on AlmaLinux 10 has a pseries-rhel machine type.
# q35 does not fall back to the default: the x86_64 default is i440fx, which UEFI cannot use.
vm_machine_type_for_arch()
{
    local arch="$1" vmhost="${2-}" generic libvirt_arch name

    generic="$(vm_machine_type_alias "$arch" "${3-}")" || return 1
    libvirt_arch="$(vm_machine_type_libvirt_arch "$arch")" || return 1
    if [ "$generic" = q35 ] ||
        vm_machine_type_supported "$vmhost" "$libvirt_arch" "$generic"; then
        printf 'machine:%s\n' "$generic"
        return
    fi
    name="$(vm_machine_type_default "$vmhost" "$libvirt_arch")"
    printf 'machine:%s\n' "${name:-$generic}"
}

# vmhost <node> -- the host whose libvirt runs the guest, empty when unset.
vm_machine_type_vmhost()
{
    lsdef "$1" -i vmhost 2>/dev/null |
        sed -n 's/^[[:space:]]*vmhost=//p' | head -n 1
}

vm_machine_type_get()
{
    local out
    if ! out="$(lsdef "$1" -i vmothersetting)"; then
        echo "vm_machine_type.sh: cannot read vmothersetting of $1" >&2
        return 1
    fi
    printf '%s\n' "$out" | sed -n 's/^[[:space:]]*vmothersetting=//p'
}

vm_machine_type_saved()
{
    local state
    vm_machine_type_private_dir || return 1
    state="$(vm_machine_type_state "$1")"
    if [ ! -e "$state" ] && [ ! -L "$state" ]; then
        echo "vm_machine_type.sh: no saved vmothersetting for $1 in $state" >&2
        return 1
    fi
    if [ -L "$state" ] || [ ! -f "$state" ] || [ ! -O "$state" ]; then
        echo "vm_machine_type.sh: $state is not a regular file of $(id -un)" >&2
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
    local node="$1" state original
    vm_machine_type_private_dir || return 1
    state="$(vm_machine_type_state "$node")"
    # A second invalid would save machine:invalid as the original value.
    if [ -e "$state" ] || [ -L "$state" ]; then
        echo "vm_machine_type.sh: a saved vmothersetting for $node already exists in $state" >&2
        return 1
    fi
    original="$(vm_machine_type_get "$node")" || return 1
    # noclobber makes bash create the file with O_EXCL.
    (set -o noclobber && printf '%s' "$original" >"$state") || return 1
    # kvm.pm uses the last machine: setting.
    if ! chdef "$node" "vmothersetting=$(vm_machine_type_join "$original" 'machine:invalid')"; then
        rm -f "$state"
        return 1
    fi
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
    if ! machine="$(vm_machine_type_for_arch "$arch" "$(vm_machine_type_vmhost "$node")" "$original")"; then
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
