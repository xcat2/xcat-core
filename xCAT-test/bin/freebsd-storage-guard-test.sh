#!/bin/sh

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin
LC_ALL=C
export PATH LC_ALL
umask 077
[ "$#" -eq 4 ]
workspace=$1 guard=$2 member1=$3 member2=$4
[ "$(id -u):$(freebsd-version -u)" = 0:15.1-RELEASE ]
[ ! -e "$workspace" ] && [ ! -L "$workspace" ]
mkdir -m 0700 "$workspace"
name=setup
finish()
{
    rc=$?
    trap - EXIT
    printf '%s\n' "$rc" > "$workspace/exit-code"
    [ "$rc" -eq 0 ] || printf 'FAIL %s\n' "$name"
    exit "$rc"
}
trap finish EXIT
. "$(dirname "$guard")/xcat-install-lib.sh"
cat > "$workspace/config" <<EOF
format=xcat-freebsd-install-4
release=15.1-RELEASE
node=node1
generation=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
master=192.0.2.1
port=3001
mac=02:00:00:00:00:01
ipv4=192.0.2.2
netmask=255.255.255.0
gateway=
hostname=node1
filesystem=zfs
swap_size=0
zfs_topology=mirror
zfs_vdevs=$member1,$member2
swap_mode=none
install_url=http://192.0.2.1/install/freebsd/
package_plan_sha256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
boot_media_sha256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
runtime_sha256=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
authorized_key_base64=YQ==
nameservers=
bootstrap=dhcp
console_port=none
console_speed=0
console_flow=none
install_boot_options_base64=
target_boot_options_base64=
EOF
xcat_read_config "$workspace/config"
disk1=${member1%%@*} disk2=${member2%%@*}
XCAT_WORK=$workspace
xcat_check_zfs_initial > "$workspace/snapshot"
sha256 "/dev/$disk1" "/dev/$disk2" > "$workspace/disks.before"
mkdir "$workspace/target" "$workspace/etc" "$workspace/boot" "$workspace/bin" "$workspace/tmp"
export BSDINSTALL_CHROOT=$workspace/target BSDINSTALL_TMPETC=$workspace/etc BSDINSTALL_TMPBOOT=$workspace/boot
export TMPDIR=$workspace/tmp
export ZFSBOOT_PARTITION_SCHEME=GPT
unset ZFSBOOT_POOL_SIZE ZFSBOOT_SWAP_ENCRYPTION ZFSBOOT_SWAP_MIRROR ZFSBOOT_BOOT_TYPE
number=0 denials=0
begin()
{
    number=$((number+1))
    name=$1 job=$workspace/job$number
    sh "$guard" "$job" arm "$workspace/config" "$workspace/snapshot"
    [ "$(sh "$guard" "$job" efi-prefix)" = xeaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ]
    sh "$guard" "$job" start "$disk1 $disk2" mirror zroot 0 '' ''
    sh "$guard" "$job" attempt
}
permit()
{
    [ "$(sh "$guard" "$job" before zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1")" = run ]
}
deny()
{
    denials=$((denials+1))
    rc=0
    sh "$guard" "$job" "$@" > "$workspace/$name.$denials.out" 2> "$workspace/$name.$denials.err" || rc=$?
    [ "$rc" -ne 0 ] && [ ! -s "$workspace/$name.$denials.out" ]
}
blocked()
{
    deny before zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1"
    [ -d "$job/busy" ] && [ ! -e "$job/ready" ]
    printf 'PASS %s\n' "$name"
}

begin missing-completion
permit
blocked

begin mismatched-completion
permit
deny after zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk2"
blocked

begin missing-native-effect
permit
deny after zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1"
blocked

begin wrong-member-order
deny before zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk2"
blocked

begin wrong-partition-scheme
deny before zfs_create_diskpart gpart 'gpart create -s %s "%s"' mbr "$disk1"
blocked

begin unexpected-native-argument
deny before zfs_create_diskpart sysctl 'sysctl vfs.zfs.vdev.min_auto_ashift=12' extra
blocked

begin wrong-completion-family
permit
deny step-after zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1"
blocked

begin forbidden-cleanup
deny before zfs_create_diskpart gpart 'gpart destroy -F "%s"' "$disk1"
blocked

begin changed-configuration
printf '\n' >> "$job/config"
deny before zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1"
cp "$workspace/config" "$job/config"
blocked

begin native-retry
deny attempt
blocked

for member in "$member1" "$member2"; do
    begin "changed-identity-${member%%@*}"
    cat > "$workspace/bin/geom" <<'EOF'
#!/bin/sh
[ "$*" = 'disk list' ] || exit 90
/sbin/geom disk list | awk -v serial="$TEST_SERIAL" '$1 == "ident:" && $2 == serial {$2="CHANGED"} {print}'
EOF
    chmod 0555 "$workspace/bin/geom"
    rc=0
    TEST_SERIAL=${member#*@} PATH="$workspace/bin:$PATH" sh "$guard" "$job" before \
        zfs_create_diskpart gpart 'gpart create -s %s "%s"' gpt "$disk1" \
        > "$workspace/$name.out" 2> "$workspace/$name.err" || rc=$?
    [ "$rc" -ne 0 ] && [ ! -s "$workspace/$name.out" ]
    blocked
done

sha256 "/dev/$disk1" "/dev/$disk2" > "$workspace/disks.after"
cmp "$workspace/disks.before" "$workspace/disks.after"
[ "$(xcat_check_zfs_initial)" = "$(cat "$workspace/snapshot")" ]
printf 'PASS complete-disk-preservation\n'
