#!/usr/bin/env bats

load '../bats/helpers/script_sandbox'

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'Disk selection requires Linux namespaces'
    [ "$(id -u)" -eq 0 ] || { echo 'Run as root to create dummy block devices' >&2; return 1; }
    setup_script_sandbox cat mkdir rm rmdir sed cut grep awk sort head tail find touch
    script="$(repo_path xCAT-server/share/xcat/install/scripts/getinstdisk)"
    [ -r "$script" ]
    mkdir -p "$fixture"/{props,dev/md,discovery}
    printf 'major minor  #blocks  name\n\n' >"$fixture/partitions"
    sandbox+=(--ro-bind "$fixture/partitions" /proc/partitions
        --ro-bind "$script" /run/getinstdisk
        --setenv MASTER_IP 192.0.2.1 --setenv log_label install)
    mv "$fixture/bin/find" "$fixture/find"
    mv "$fixture/bin/awk" "$fixture/awk"
    cat >"$fixture/bin/find" <<'SH'
#!/bin/sh
case "$1" in
    /usr/*) exec /run/fixture/find /run/fixture/discovery -name awk ;;
    *) exec /run/fixture/find "$@" ;;
esac
SH
    cat >"$fixture/bin/udevadm" <<'SH'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        info) shift ;;
        --name=*) name=${1#--name=}; shift ;;
        --name|-n) name=$2; shift 2 ;;
        --query=*) query=${1#--query=}; shift ;;
        --query|-q) query=$2; shift 2 ;;
        --attribute-walk|-a) query=attributes; shift ;;
        *) exit 97 ;;
    esac
done
name=${name#/dev/}
case "$query" in
    property) cat "/run/fixture/props/$name.props" ;;
    attributes) cat "/run/fixture/props/$name.attrs" ;;
    *) exit 97 ;;
esac
SH
    chmod +x "$fixture/bin/"{find,udevadm}
    command='. /run/getinstdisk'
}

disk()
{
    local name=$1 driver=${2:-} wwn=${3:-} device_path=${4:-} size=${5:-1024000000}
    printf '   8 0 524288000 %s\n' "$name" >>"$fixture/partitions"
    printf 'DEVTYPE=disk\nID_WWN=%s\nDEVPATH=%s\n' "$wwn" "$device_path" >"$fixture/props/$name.props"
    printf '    ATTRS{size}=="%s"\n    DRIVERS=="%s"\n' "$size" "$driver" >"$fixture/props/$name.attrs"
}

device()
{
    local name=$1 type=${2:-block}
    if [ "$type" = block ]; then
        mknod "$fixture/dev/$name" b 240 0
    else
        : >"$fixture/dev/$name"
    fi
    sandbox+=(--ro-bind "$fixture/dev/$name" "/dev/$name")
}

selects()
{
    local expected=$1 discovery pass
    for discovery in present absent; do
        if [ "$discovery" = present ]; then
            cp "$fixture/awk" "$fixture/bin/awk"
            : >"$fixture/discovery/awk"
        else
            rm "$fixture/discovery/awk" "$fixture/bin/awk"
        fi
        for pass in 1 2; do
            printf '/dev/not-selected\n' >"$fixture/tmp/xcat.install_disk"
            run "${sandbox[@]}" timeout --kill-after=5 45 /bin/sh -c "$command"
            [ "$status" -eq 0 ] || { echo "$discovery awk, pass $pass: $output"; return 1; }
            printf '%s\n' "$expected" >"$fixture/expected-disk"
            cmp "$fixture/expected-disk" "$fixture/tmp/xcat.install_disk"
            [ ! -e "$fixture/tmp/xcat.getinstalldisk" ]
            [[ "$output" != *'not found'* ]]
        done
    done
}

@test "direct disks take priority over RAID disks" {
    disk sda megaraid_sas
    disk sdb ahci
    selects /dev/sdb
}

@test "a RAID disk is selected when no direct disk exists" {
    disk sda megaraid_sas
    selects /dev/sda
}

@test "direct disks take priority over SAS disks" {
    disk sda mpt3sas
    disk sdb ahci
    selects /dev/sdb
}

@test "SAS disks take priority over unclassified drivers" {
    disk sda mpt3sas
    disk sdb virtio_blk
    selects /dev/sda
}

@test "a driverless NVMe disk can be selected" {
    disk nvme0n1
    selects /dev/nvme0n1
}

@test "an empty scan falls back to sda" {
    selects /dev/sda
}

@test "driver priority wins over a RAID WWN" {
    disk sda megaraid_sas 0x5001
    disk sdb ahci
    selects /dev/sdb
}

@test "driver priority also wins when the direct disk is scanned first" {
    disk sda ahci
    disk sdb megaraid_sas 0x5002
    selects /dev/sda
}

@test "a WWN takes priority over a missing identifier within a driver group" {
    disk sda ahci
    disk sdb ahci 0x5001
    selects /dev/sdb
}

@test "the lower WWN wins within a driver group" {
    disk sda ahci 0x5002
    disk sdb ahci 0x5001
    selects /dev/sdb
}

@test "a device path takes priority over a missing identifier" {
    disk sda ahci '' /devices/pci/block/sda
    disk sdb ahci
    selects /dev/sda
}

@test "a scanned Xen disk can be selected" {
    disk xvda vbd
    selects /dev/xvda
}

@test "Xen disks follow driver priority" {
    disk xvda vbd
    disk xvdb ahci
    selects /dev/xvdb
}

@test "small media is ignored even with a preferred driver" {
    disk sda ahci '' '' 100
    disk sdb virtio_blk
    selects /dev/sdb
}

@test "the numbered VROC volume is a fallback" {
    device md/Volume0_0
    selects /dev/md/Volume0_0
}

@test "the unnumbered VROC volume is a fallback" {
    device md/Volume0
    selects /dev/md/Volume0
}

@test "the numbered VROC volume takes priority over other fallbacks" {
    device md/Volume0_0
    device md/Volume0
    device xvda
    selects /dev/md/Volume0_0
}

@test "a Xen block device is a fallback" {
    device xvda
    selects /dev/xvda
}

@test "a scanned disk takes priority over fallback devices" {
    disk sdb ahci
    device md/Volume0_0
    device xvda
    selects /dev/sdb
}

@test "regular files are not fallback block devices" {
    device md/Volume0_0 regular
    device md/Volume0 regular
    device xvda regular
    selects /dev/sda
}

@test "default selection reports a warning when the installer logger exists" {
    command='msgutil_r() { printf "%s\n" "$*" >>/run/fixture/warnings; }; . /run/getinstdisk'
    selects /dev/sda
    for pass in 1 2 3 4; do
        printf '%s\n' '192.0.2.1 warn Disk detection failed, defaulting to /dev/sda /var/log/xcat/xcat.log install'
    done >"$fixture/expected-warnings"
    cmp "$fixture/expected-warnings" "$fixture/warnings"
}
