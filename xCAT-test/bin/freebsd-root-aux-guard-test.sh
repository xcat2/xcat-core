#!/bin/sh

# Run on a disposable BIOS guest with empty, explicitly selected OS disks.
# Successful execution leaves all selected OS disks partitioned.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 3 ]
workspace=$1 guard=$2 config=$3
[ "$(id -u):$(freebsd-version -u):$(sysctl -n machdep.bootmethod)" = 0:15.1-RELEASE:BIOS ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
. "$(dirname "$guard")/xcat-install-lib.sh"
xcat_read_config "$config"
[ "$XCAT_FORMAT:$XCAT_DISK_ACTION:$XCAT_ZFS_TOPOLOGY" = xcat-freebsd-install-6:empty:mirror ]
primary=$(xcat_zfs_members)
special=$(xcat_zfs_auxiliary | awk -F '\t' '$3~/^special:/ {print $1}')
auxiliary=$(xcat_zfs_auxiliary | cut -f1)
[ "$(printf '%s\n' "$primary" | wc -l)" -eq 2 ]
[ "$(printf '%s\n' "$special" | wc -l)" -eq 2 ]
XCAT_WORK=$workspace
kldload -n zfs
kldload -n geom_eli
xcat_check_zfs_initial > "$workspace/snapshot"
mkdir "$workspace/target" "$workspace/etc" "$workspace/boot" "$workspace/tmp"
export BSDINSTALL_CHROOT=$workspace/target BSDINSTALL_TMPETC=$workspace/etc BSDINSTALL_TMPBOOT=$workspace/boot
export TMPDIR=$workspace/tmp ZFSBOOT_PARTITION_SCHEME=GPT
unset ZFSBOOT_POOL_SIZE ZFSBOOT_SWAP_ENCRYPTION ZFSBOOT_SWAP_MIRROR ZFSBOOT_BOOT_TYPE ZFSBOOT_FORCE_4K_SECTORS
job=$workspace/job
sh "$guard" "$job" arm "$config" "$workspace/snapshot"
prefix=$(sh "$guard" "$job" zfs-prefix)
[ "$prefix" = "z$XCAT_GENERATION" ]
disks=$(printf '%s\n' "$primary" | awk '{s=s (NR==1 ? "" : " ") $1} END {print s}')
sh "$guard" "$job" start "$disks" mirror zroot 0 '' ''
sh "$guard" "$job" attempt
before()
{
    [ "$(sh "$guard" "$job" before zfs_create_diskpart "$@")" = run ]
}
after()
{
    sh "$guard" "$job" after zfs_create_diskpart "$@"
}
index=0
for disk in $disks; do
    set -- gpart 'gpart create -s %s "%s"' gpt "$disk"
    before "$@"
    gpart create -s gpt "$disk"
    after "$@"
    set -- gpart 'gpart add %s -l %s -t %s -s %s "%s"' '-a 4k' "gptboot$index" freebsd-boot 512k "$disk"
    before "$@"
    gpart add -a 4k -l "gptboot$index" -t freebsd-boot -s 512k "$disk"
    after "$@"
    set -- gpart 'gpart add %s -l %s -t %s "%s"' '-a 1m' "$prefix$index" freebsd-zfs "$disk"
    before "$@"
    gpart add -a 1m -l "$prefix$index" -t freebsd-zfs "$disk"
    after "$@"
    set -- gpart 'gpart bootcode -b "%s" -p "%s" -i %s "%s"' /boot/pmbr /boot/gptzfsboot 1 "$disk"
    before "$@"
    gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "$disk"
    after "$@"
    set -- zpool 'zpool labelclear -f "%s"' "/dev/${disk}p2"
    [ "$(sh "$guard" "$job" before zfs_create_diskpart "$@")" = skip ]
    after "$@"
    sh "$guard" "$job" partitioned "$disk" p2
    index=$((index+1))
done
index=0
for disk in $auxiliary; do
    gpart show -p "$disk" | awk -v disk="$disk" '
        $3==disk "p1" {found++; if($4!="freebsd-zfs") bad=1}
        $3 ~ ("^" disk "p[0-9]+$") && $3!=disk "p1" {bad=1}
        END {exit found!=1 || bad}'
    gpart list "$disk" | awk -v label="a$XCAT_GENERATION$index" '$1=="label:" {found++; if($2!=label)bad=1} END {exit found!=1 || bad}'
    [ -c "/dev/gpt/a$XCAT_GENERATION$index" ]
    index=$((index+1))
done
printf 'PASS all auxiliary partitions and stable GPT names created through the native guard\n'
options="-o altroot=$BSDINSTALL_CHROOT -o ashift=$XCAT_ZFS_ASHIFT -O compression=$XCAT_ZFS_COMPRESSION -O atime=off -O special_small_blocks=$XCAT_ZFS_SPECIAL_SMALL_BLOCKS -o cachefile=none -m none "
leaves="/dev/gpt/z${XCAT_GENERATION}0 /dev/gpt/z${XCAT_GENERATION}1"
aux=$(xcat_zfs_auxiliary arguments | awk '{s=s (NR==1 ? "" : " ") $0} END {print s}')
expected="$leaves $aux"
clone()
{
    job=$workspace/$1
    cp -Rp "$workspace/job" "$job"
}
create_request()
{
    sh "$guard" "$job" before zfs_create_diskpart zpool 'zpool create %s "%s" %s %s' "$options" zroot mirror "$1"
}
hashes()
{
    for disk in $(xcat_zfs_all_members | cut -f1); do
        printf '%s ' "$disk"
        (rc=0; dd if="/dev/$disk" bs=1m 2> "$workspace/hash-$disk.log" || rc=$?; printf '%s\n' "$rc" > "$workspace/hash-$disk.status") | sha256 -q
        [ "$(cat "$workspace/hash-$disk.status")" = 0 ]
    done
}
hashes > "$workspace/before-denials.sha256"
first_special=$(printf '%s\n' "$special" | head -n 1)
first_primary=$(printf '%s\n' "$primary" | head -n 1 | cut -f1)
for kind in raw-special missing-special unmirrored-special wrong-role wrong-partition unstable-primary unstable-log unstable-cache; do
    clone "$kind"
    case "$kind" in
        raw-special) given=$(printf '%s\n' "$expected" | sed "s@/dev/gpt/a${XCAT_GENERATION}0@/dev/$first_special@") ;;
        missing-special) given=$(printf '%s\n' "$expected" | sed "s@/dev/gpt/a${XCAT_GENERATION}0@@") ;;
        unmirrored-special) given=$(printf '%s\n' "$expected" | sed 's/special mirror/special/') ;;
        wrong-role) given=$(printf '%s\n' "$expected" | sed 's/special mirror/log mirror/') ;;
        wrong-partition) given=$(printf '%s\n' "$expected" | sed "s@/dev/gpt/a${XCAT_GENERATION}0@/dev/${first_special}p2@") ;;
        unstable-primary) given=$(printf '%s\n' "$expected" | sed "s@/dev/gpt/z${XCAT_GENERATION}0@/dev/${first_primary}p2@") ;;
        unstable-log|unstable-cache)
            role=${kind#unstable-}
            row=$(xcat_zfs_auxiliary partitions | awk -F '\t' -v role="$role" '$3~("^" role ":") {print; exit}')
            [ -n "$row" ]
            disk=$(printf '%s\n' "$row" | cut -f1)
            label=$(printf '%s\n' "$row" | cut -f4)
            given=$(printf '%s\n' "$expected" | sed "s@/dev/gpt/$label@/dev/${disk}p1@") ;;
    esac
    if create_request "$given" > "$workspace/$kind.out" 2> "$workspace/$kind.err"; then exit 1; fi
    [ ! -s "$workspace/$kind.out" ] && [ -f "$job/failed" ]
    if create_request "$expected" > "$workspace/$kind-retry.out" 2> "$workspace/$kind-retry.err"; then exit 1; fi
    [ ! -s "$workspace/$kind-retry.out" ]
    printf 'PASS %s rejected and retry blocked\n' "$kind"
done
clone valid-create
[ "$(create_request "$expected")" = run ]
[ -f "$job/busy/approved" ] && [ ! -e "$job/failed" ]
hashes > "$workspace/after-denials.sha256"
cmp "$workspace/before-denials.sha256" "$workspace/after-denials.sha256"
printf 'PASS exact pool arguments approved without disk writes\n'
clone changed-special-layout
disk=$(printf '%s\n' "$special" | head -n 1)
gpart modify -i 1 -t freebsd-ufs "$disk"
if create_request "$expected" > "$workspace/changed-layout.out" 2> "$workspace/changed-layout.err"; then exit 1; fi
[ ! -s "$workspace/changed-layout.out" ] && [ -f "$job/failed" ]
gpart modify -i 1 -t freebsd-zfs "$disk"
[ -z "$(zpool list -H -o name)" ]
printf 'PASS changed special partition type rejected\n'
