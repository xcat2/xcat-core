#!/bin/bash
# Read back the SELinux context of the Genesis kernel that mknb stages into the TFTP root.
#
# Usage: selinux_context.sh <arch>
#
# The caller asserts on one of three tokens, so no error message can carry the token of a pass:
#   GENESIS_SELINUX_OK        the staged kernel carries the context the policy declares
#   GENESIS_SELINUX_SKIPPED   SELinux is off, or the tools to read a context are absent
#   GENESIS_SELINUX_FAIL      the context is wrong, or the kernel was not staged

arch="$1"
if [ -z "$arch" ]; then
    echo "GENESIS_SELINUX_FAIL: no architecture given"
    exit 1
fi

tftpdir=$(lsdef -t site -i tftpdir 2>/dev/null | sed -n 's/^[[:space:]]*tftpdir=//p')
[ -n "$tftpdir" ] || tftpdir=/tftpboot
kernel="$tftpdir/xcat/genesis.kernel.$arch"

if ! command -v selinuxenabled >/dev/null 2>&1; then
    echo "GENESIS_SELINUX_SKIPPED: selinuxenabled is absent, so no context can be read"
    exit 0
fi
if ! selinuxenabled; then
    echo "GENESIS_SELINUX_SKIPPED: SELinux is disabled on $(hostname)"
    exit 0
fi
# A permissive node applies labels, so it is measured like an enforcing one.
echo "SELinux mode on $(hostname): $(getenforce)"
if ! command -v restorecon >/dev/null 2>&1; then
    echo "GENESIS_SELINUX_FAIL: SELinux is enabled and restorecon is absent"
    exit 1
fi

# cp keeps the context of a destination that already exists, so a correct label from an earlier
# run hides the defect.
rm -f "$kernel"
if ! mknb "$arch"; then
    echo "GENESIS_SELINUX_FAIL: mknb $arch returned non-zero"
    exit 1
fi
if [ ! -f "$kernel" ]; then
    echo "GENESIS_SELINUX_FAIL: mknb $arch staged no $kernel"
    exit 1
fi
echo "Context of $kernel: $(stat -c %C "$kernel")"

# restorecon names each file whose context differs from the policy. -F compares the whole
# context, which is what mknb applies.
difference=$(restorecon -F -n -v "$kernel" 2>&1)
if [ -n "$difference" ]; then
    echo "$difference"
    echo "GENESIS_SELINUX_FAIL: the staged kernel does not carry the context of the policy"
    exit 1
fi
echo "GENESIS_SELINUX_OK: the staged kernel carries the context the policy declares"
exit 0
