#!/usr/bin/env bats
#
# Drive mount_snapshot.sh, which the diskless cases use to compare the mount table before and
# after genimage. The comparison exists to catch a bind mount genimage leaves inside the root
# image, and it must keep catching one.
#
# The snapshots below are real lines from an openEuler 22.03 management node. On that run
# binfmt_misc and tracefs appeared between the two snapshots and failed the case, so the first
# test holds down that they are ignored. The second test is the one that matters: a leaked
# genimage bind must still be reported, which is why filtering by filesystem type is wrong.

load 'helpers/shell_source'

ROOTIMG=/install/netboot/openeuler22.03sp4/x86_64/compute/rootimg

setup()
{
    SCRIPT="$(require_repo_file 'xCAT-test/autotest/testcase/commoncmd/mount_snapshot.sh')"
    BEFORE="${BATS_TEST_TMPDIR}/file.org"
    AFTER="${BATS_TEST_TMPDIR}/file.new"

    cat >"$BEFORE" <<EOF
/dev/vda2 on / type xfs (rw,relatime,attr2,inode64,logbufs=8,logbsize=32k,noquota)
devtmpfs on /dev type devtmpfs (rw,nosuid,size=4096k,nr_inodes=1048576,mode=755)
proc on /proc type proc (rw,nosuid,nodev,noexec,relatime)
sysfs on /sys type sysfs (rw,nosuid,nodev,noexec,relatime)
systemd-1 on /proc/sys/fs/binfmt_misc type autofs (rw,relatime,fd=34,pgrp=1,timeout=0)
tmpfs on /run type tmpfs (rw,nosuid,nodev,size=1985536k,mode=755)
tracefs on /sys/kernel/tracing type tracefs (rw,nosuid,nodev,noexec,relatime)
EOF
}

# The kernel may mount either of these at any moment. Neither is xCAT's doing.
@test "an on-demand kernel mount appearing during genimage is ignored" {
    cp "$BEFORE" "$AFTER"
    cat >>"$AFTER" <<EOF
binfmt_misc on /proc/sys/fs/binfmt_misc type binfmt_misc (rw,nosuid,nodev,noexec,relatime)
tracefs on /sys/kernel/debug/tracing type tracefs (rw,nosuid,nodev,noexec,relatime)
EOF

    diff <("$SCRIPT" "$BEFORE") <("$SCRIPT" "$AFTER")
}

# The discriminator. A leaked bind is a proc mount, so a type filter would drop it and the
# comparison could never fail again.
@test "a bind mount genimage left inside the root image is still reported" {
    cp "$BEFORE" "$AFTER"
    printf 'proc on %s/proc type proc (rw,nosuid,nodev,noexec,relatime)\n' "$ROOTIMG" >>"$AFTER"

    run diff <("$SCRIPT" "$BEFORE") <("$SCRIPT" "$AFTER")
    [ "$status" -ne 0 ]
    [[ "$output" == *"$ROOTIMG/proc"* ]]
}

# An ordinary mount outside /proc and /sys is the other half of the same requirement.
@test "an NFS mount left behind is still reported" {
    cp "$BEFORE" "$AFTER"
    printf '192.0.2.1:/install on /mnt/install type nfs4 (rw,relatime)\n' >>"$AFTER"

    run diff <("$SCRIPT" "$BEFORE") <("$SCRIPT" "$AFTER")
    [ "$status" -ne 0 ]
    [[ "$output" == *"/mnt/install"* ]]
}

@test "the snapshot keeps the real mounts and drops only the kernel's own" {
    run "$SCRIPT" "$BEFORE"
    [ "$status" -eq 0 ]
    [[ "$output" == *" on / type xfs"* ]]
    [[ "$output" == *" on /run type tmpfs"* ]]
    [[ "$output" == *" on /dev type devtmpfs"* ]]
    refute_grep -q ' on /proc ' <<<"$output"
    refute_grep -q ' on /sys ' <<<"$output"
    refute_grep -q '/sys/kernel/tracing' <<<"$output"
}
