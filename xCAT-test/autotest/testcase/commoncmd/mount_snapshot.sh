#!/bin/sh
#
# mount_snapshot.sh [<file>]
#
# Print the mount table without the kernel's own on-demand mounts, so the diskless cases can
# compare a snapshot taken before genimage with one taken after it.
#
# genimage bind mounts /proc, /sys and /dev inside the root image. A bind it fails to remove
# leaves the next image built on top of the host, so comparing the two snapshots is worth doing.
#
# What the comparison must not assert is that nothing else mounted anything meanwhile.
# binfmt_misc is an autofs stub that becomes a real mount the first time a process reads
# /proc/sys/fs/binfmt_misc, and tracefs appears under /sys/kernel/debug the first time anything
# opens debugfs tracing. Both are the kernel's doing and both can happen during genimage. On one
# openEuler 22.03 run both did, and the case failed four minutes in while the provisioning that
# followed succeeded.
#
# Filtering by filesystem type would hide the leak this guards, because a leaked genimage bind IS
# a proc or sysfs mount. The mount POINT separates them: the kernel keeps its on-demand mounts
# inside /proc and /sys, and a leaked bind sits under the root image directory.
#
# With a file argument, filter that file instead of asking the kernel, so the filter is testable.

set -e

if [ $# -ge 1 ]; then
    cat -- "$1"
else
    mount
fi | awk '$3 !~ /^\/(proc|sys)(\/|$)/' | sort
