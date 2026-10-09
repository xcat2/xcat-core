#!/bin/bash
# vm_machine_type.sh - set and clear the KVM machine type in vmothersetting of a node.
#
# Usage:
#   vm_machine_type.sh invalid <node>          add machine:invalid, so the VM cannot start
#   vm_machine_type.sh apply <node> <arch>     replace machine:invalid with a valid type
#   vm_machine_type.sh restore <node> <arch>   remove the valid type again

vm_machine_type_for_arch()
{
    local arch="$1" str3
    if [[ "$arch" =~ "ppc64" ]]; then str3="machine:pseries-rhel7.6.0"; elif [[ "$arch" =~ "x86_64" ]]; then str3="machine:pc"; elif [[ "$arch" =~ "riscv64" ]]; then str3="machine:virt"; elif [[ "$arch" =~ "aarch64" ]]; then str3="machine:virt";fi
    printf '%s\n' "$str3"
}

vm_machine_type_invalid()
{
    local node="$1" str1 str2 str3 str4
    str1=`lsdef $node | grep vmothersetting | cut -d '=' -f 2`;str2=";"; str3="machine:invalid"; if [ -z $str1 ]; then str4=$str3; else str4=$str1$str2$str3;fi; chdef $node vmothersetting=$str4
}

vm_machine_type_apply()
{
    local node="$1" arch="$2" str1 str2 str3 str4 str5
    str1=`lsdef $node | grep vmothersetting | cut -d '=' -f 2`;str2="machine:invalid"; str3=$(vm_machine_type_for_arch "$arch"); if [ "$str1" == "$str2" ]; then str5=$str3; else str4=`echo $str1 | sed -e "s/$str2//"`;str5=$str4$str3;fi; chdef $node vmothersetting=$str5
}

vm_machine_type_restore()
{
    local node="$1" arch="$2" str1 str2 str3 str4
    str1=`lsdef $node | grep vmothersetting | cut -d '=' -f 2`;str2=";"; str3=$(vm_machine_type_for_arch "$arch"); if [ "$str1" == "$str3" ]; then chdef $node vmothersetting=; else str4=`echo $str1 | sed -e "s/$str2$str3//"`; chdef $node vmothersetting=$str4;fi
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
            echo "usage: vm_machine_type.sh {invalid <node>|apply <node> <arch>|restore <node> <arch>}" >&2
            return 2
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    vm_machine_type_main "$@"
fi
