#!/bin/sh

xcat_error()
{
    printf 'xCAT FreeBSD: %s\n' "$*" >&2
    return 1
}

xcat_ipv4()
{
    printf '%s\n' "$1" | awk -F. 'NF != 4 {exit 1} {for (i=1;i<=4;i++) if ($i !~ /^[0-9]+$/ || length($i)>3 || $i+0>255 || (length($i)>1 && substr($i,1,1)=="0")) exit 1}'
}

xcat_hex()
{
    [ "${#1}" -eq "$2" ] || return 1
    case "$1" in *[!0-9a-f]*) return 1 ;; esac
}

xcat_url()
{
    printf '%s\n' "$1" | awk '
        !/^https?:\/\/[A-Za-z0-9.-]+(:[0-9]+)?\/[A-Za-z0-9_.+\/-]+$/ {exit 1}
        /\/\.\.?($|\/)/ {exit 1}'
}

xcat_read_config()
{
    XCAT_FORMAT= XCAT_RELEASE= XCAT_NODE= XCAT_GENERATION= XCAT_MASTER= XCAT_PORT=
    XCAT_MAC= XCAT_IPV4= XCAT_NETMASK= XCAT_GATEWAY= XCAT_HOSTNAME=
    XCAT_TARGET_DISK= XCAT_TARGET_DISK_IDENT= XCAT_FILESYSTEM= XCAT_SWAP_SIZE=
    XCAT_DIST_URL= XCAT_BASE_SHA256= XCAT_KERNEL_SHA256= XCAT_AUTHORIZED_KEY_BASE64=
    XCAT_NAMESERVERS= xcat_seen=' '
    while IFS= read -r xcat_line || [ -n "$xcat_line" ]; do
        case "$xcat_line" in ''|'#'*) continue ;; *=*) ;; *) xcat_error 'Malformed configuration'; return 1 ;; esac
        xcat_key=${xcat_line%%=*}
        xcat_value=${xcat_line#*=}
        case "$xcat_seen" in *" $xcat_key "*) xcat_error "Duplicate field: $xcat_key"; return 1 ;; esac
        xcat_seen="$xcat_seen$xcat_key "
        case "$xcat_key" in
            format) XCAT_FORMAT=$xcat_value ;;
            release) XCAT_RELEASE=$xcat_value ;;
            node) XCAT_NODE=$xcat_value ;;
            generation) XCAT_GENERATION=$xcat_value ;;
            master) XCAT_MASTER=$xcat_value ;;
            port) XCAT_PORT=$xcat_value ;;
            mac) XCAT_MAC=$xcat_value ;;
            ipv4) XCAT_IPV4=$xcat_value ;;
            netmask) XCAT_NETMASK=$xcat_value ;;
            gateway) XCAT_GATEWAY=$xcat_value ;;
            hostname) XCAT_HOSTNAME=$xcat_value ;;
            target_disk) XCAT_TARGET_DISK=$xcat_value ;;
            target_disk_ident) XCAT_TARGET_DISK_IDENT=$xcat_value ;;
            filesystem) XCAT_FILESYSTEM=$xcat_value ;;
            swap_size) XCAT_SWAP_SIZE=$xcat_value ;;
            dist_url) XCAT_DIST_URL=$xcat_value ;;
            base_sha256) XCAT_BASE_SHA256=$xcat_value ;;
            kernel_sha256) XCAT_KERNEL_SHA256=$xcat_value ;;
            authorized_key_base64) XCAT_AUTHORIZED_KEY_BASE64=$xcat_value ;;
            nameservers) XCAT_NAMESERVERS=$xcat_value ;;
            *) xcat_error "Unknown field: $xcat_key"; return 1 ;;
        esac
    done < "$1"
    [ "$XCAT_FORMAT" = xcat-freebsd-install-1 ] && [ "$XCAT_RELEASE" = 15.1-RELEASE ] || return 1
    for xcat_name in "$XCAT_NODE" "$XCAT_HOSTNAME"; do
        case "$xcat_name" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    done
    xcat_hex "$XCAT_GENERATION" 32 && xcat_hex "$XCAT_BASE_SHA256" 64 && xcat_hex "$XCAT_KERNEL_SHA256" 64 || return 1
    for xcat_address in "$XCAT_MASTER" "$XCAT_IPV4" "$XCAT_NETMASK"; do xcat_ipv4 "$xcat_address" || return 1; done
    printf '%s\n' "$XCAT_NETMASK" | awk -F. '{for(i=1;i<=4;i++) {
        if (partial && $i != 0) exit 1
        if ($i !~ /^(255|254|252|248|240|224|192|128|0)$/) exit 1
        if ($i != 255) partial=1
    }}' || return 1
    [ -z "$XCAT_GATEWAY" ] || xcat_ipv4 "$XCAT_GATEWAY" || return 1
    case "$XCAT_PORT" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#XCAT_PORT}" -le 5 ] && [ "$XCAT_PORT" -gt 0 ] && [ "$XCAT_PORT" -le 65535 ] || return 1
    printf '%s\n' "$XCAT_MAC" | awk '!/^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$/ {exit 1}' || return 1
    printf '%s\n' "$XCAT_TARGET_DISK" | awk '!/^(ada|da|nda|nvd|vtbd)[0-9]+$/ {exit 1}' || return 1
    case "$XCAT_TARGET_DISK_IDENT" in ''|*[!A-Za-z0-9_.:+-]*) return 1 ;; esac
    case "$XCAT_FILESYSTEM" in ufs|zfs) ;; *) return 1 ;; esac
    printf '%s\n' "$XCAT_SWAP_SIZE" | awk '!/^(0|[1-9][0-9]*[mMgG])$/ || length($0)>6 {exit 1}' || return 1
    xcat_url "$XCAT_DIST_URL" || return 1
    case "$XCAT_AUTHORIZED_KEY_BASE64" in ''|*[!A-Za-z0-9+/=]*) return 1 ;; esac
    case "$XCAT_NAMESERVERS" in ,*|*,|*,,*) return 1 ;; esac
    xcat_oldifs=$IFS
    IFS=,
    for xcat_address in $XCAT_NAMESERVERS; do
        xcat_ipv4 "$xcat_address" || { IFS=$xcat_oldifs; return 1; }
    done
    IFS=$xcat_oldifs
}

xcat_find_interface()
{
    xcat_mac=$1
    xcat_match=
    for xcat_interface in $(ifconfig -l); do
        case "$xcat_interface" in [!A-Za-z]*|*[!A-Za-z0-9]*) continue ;; esac
        xcat_ether=$(ifconfig "$xcat_interface" | awk '$1 == "ether" {print tolower($2)}') || return 1
        [ "$xcat_ether" = "$xcat_mac" ] || continue
        [ -z "$xcat_match" ] || { xcat_error 'Provisioning MAC matches multiple interfaces'; return 1; }
        xcat_match=$xcat_interface
    done
    [ -n "$xcat_match" ] || { xcat_error 'Provisioning interface not found'; return 1; }
    printf '%s\n' "$xcat_match"
}

xcat_status()
{
    xcat_phase=$1
    case "$xcat_phase" in begin|complete|failed|booted) ;; *) return 1 ;; esac
    xcat_hex "$XCAT_GENERATION" 32 && xcat_hex "$XCAT_ATTEMPT" 32 || return 1
    for xcat_retry in 1 2 3; do
        xcat_response=$(printf 'freebsd-install-v1 %s %s %s\n' "$XCAT_GENERATION" "$XCAT_ATTEMPT" "$xcat_phase" |
            nc -w 15 "$XCAT_MASTER" "$XCAT_PORT") || continue
        [ "$xcat_response" = "$(printf 'ready\nfreebsd-install-v1 %s %s ok' "$XCAT_GENERATION" "$xcat_phase")" ] && return 0
    done
    xcat_error "Controller did not acknowledge $xcat_phase"
}

xcat_check_disk()
{
    xcat_disk_info=$(geom disk list "$XCAT_TARGET_DISK") || return 1
    xcat_ident=$(printf '%s\n' "$xcat_disk_info" | awk '$1 == "ident:" {print $2}')
    [ "$xcat_ident" = "$XCAT_TARGET_DISK_IDENT" ] || { xcat_error 'Target disk identity does not match'; return 1; }
    xcat_mode=$(printf '%s\n' "$xcat_disk_info" | awk '$1 == "Mode:" {print $2}')
    [ "$xcat_mode" = r0w0e0 ] || { xcat_error 'Target disk is in use'; return 1; }
    xcat_capacity=$(printf '%s\n' "$xcat_disk_info" | awk '$1 == "Mediasize:" {print $2}')
    case "$xcat_capacity" in ''|*[!0-9]*) return 1 ;; esac
    xcat_swap_bytes=$(printf '%s\n' "$XCAT_SWAP_SIZE" | awk '/[gG]$/ {print ($0+0)*1073741824; next} /[mM]$/ {print ($0+0)*1048576; next} {print 0}')
    [ "$xcat_capacity" -ge 4294967296 ] &&
        awk -v capacity="$xcat_capacity" -v swap="$xcat_swap_bytes" 'BEGIN {exit capacity < swap+2147483648}' ||
        { xcat_error 'Target disk has insufficient capacity'; return 1; }
    xcat_pools=$(zpool list -H -o name) || return 1
    [ -z "$xcat_pools" ] || { xcat_error 'Imported ZFS pools prevent installation'; return 1; }
    xcat_geli=$(geli status -s) || return 1
    [ -z "$xcat_geli" ] || { xcat_error 'Attached GELI providers prevent installation'; return 1; }
}

xcat_scan_labels()
{
    XCAT_CLEAR_LABELS=
    xcat_disks=$(sysctl -n kern.disks) || return 1
    case " $xcat_disks " in *" $XCAT_TARGET_DISK "*) ;; *) return 1 ;; esac
    xcat_partition_list=$(gpart list) || { xcat_error 'Cannot enumerate disk partitions'; return 1; }
    for xcat_disk in $xcat_disks; do
        case "$xcat_disk" in [!A-Za-z]*|*[!A-Za-z0-9]*) return 1 ;; esac
        xcat_parts=$(printf '%s\n' "$xcat_partition_list" | awk -v disk="$xcat_disk" '
            function provider_name(name) {
                return name ~ /^[A-Za-z0-9_.+-]+(\/[A-Za-z0-9_.+-]+)*$/ && name !~ /(^|\/)\.\.?($|\/)/
            }
            function descend(parent, i, child) {
                if (visiting[parent]++) exit 1
                for (i=1; i<=count[parent]; i++) {
                    child=children[parent,i]
                    if (seen[child]++) exit 1
                    print child
                    descend(child)
                }
                visiting[parent]--
            }
            NF {content=1}
            $1 == "Geom" && $2 == "name:" {parent=$3; providers=0; geoms++}
            $1 == "Providers:" {providers=1}
            $1 == "Consumers:" {providers=0}
            providers && $2 == "Name:" {
                if (!provider_name(parent) || !provider_name($3)) bad=1
                children[parent,++count[parent]]=$3
            }
            END {if (bad || (content && !geoms)) exit 1; descend(disk)}') ||
            { xcat_error 'Cannot resolve disk partitions'; return 1; }
        for xcat_provider in "$xcat_disk" $xcat_parts; do
            xcat_label_status=0
            xcat_labels=$(zdb -l "/dev/$xcat_provider" 2>/dev/null) || xcat_label_status=$?
            case "$xcat_label_status" in
                0) ;;
                2) continue ;;
                *) xcat_error "Cannot inspect ZFS labels on $xcat_provider"; return 1 ;;
            esac
            printf '%s\n' "$xcat_labels" | awk '$1 == "pool_guid:" {found=1} END {exit !found}' ||
                { xcat_error "Cannot identify ZFS labels on $xcat_provider"; return 1; }
            if [ "$xcat_disk" != "$XCAT_TARGET_DISK" ]; then
                if [ "$XCAT_FILESYSTEM" = zfs ] && printf '%s\n' "$xcat_labels" | awk '$1 == "name:" && $2 == "\047zroot\047" {found=1} END {exit !found}'; then
                    xcat_error 'An unselected disk contains a zroot pool'; return 1
                fi
                continue
            fi
            # A single-disk reinstall must not remove a member of a larger pool.
            printf '%s\n' "$xcat_labels" | awk '
                $1 == "vdev_children:" {found=1; if ($2 != 1) bad=1}
                $1 == "type:" && $2 != "\047disk\047" {bad=1}
                END {exit (!found || bad)}' || { xcat_error 'Target belongs to an unsupported ZFS topology'; return 1; }
            XCAT_CLEAR_LABELS="$XCAT_CLEAR_LABELS /dev/$xcat_provider"
        done
    done
}

xcat_fetch_distributions()
{
    mkdir -p "$XCAT_WORK/dist" || return 1
    fetch -T 60 -o "$XCAT_WORK/dist/base.txz" "$XCAT_DIST_URL/base.txz" &&
        fetch -T 60 -o "$XCAT_WORK/dist/kernel.txz" "$XCAT_DIST_URL/kernel.txz" || return 1
    [ "$(sha256 -q "$XCAT_WORK/dist/base.txz")" = "$XCAT_BASE_SHA256" ] &&
        [ "$(sha256 -q "$XCAT_WORK/dist/kernel.txz")" = "$XCAT_KERNEL_SHA256" ] ||
        { xcat_error 'Distribution checksum does not match'; return 1; }
    fetch -T 60 -o "$XCAT_WORK/dist/MANIFEST" "$XCAT_DIST_URL/MANIFEST" || return 1
    awk -F '\t' -v base="$XCAT_BASE_SHA256" -v kernel="$XCAT_KERNEL_SHA256" '
        $1 == "base.txz" {b++; if ($2 != base || $3 !~ /^[1-9][0-9]*$/ || NF < 6) bad=1}
        $1 == "kernel.txz" {k++; if ($2 != kernel || $3 !~ /^[1-9][0-9]*$/ || NF < 6) bad=1}
        END {exit (b != 1 || k != 1 || bad)}' "$XCAT_WORK/dist/MANIFEST" ||
        xcat_error 'Distribution manifest does not match the selected files'
}

xcat_validate_key()
{
    printf '%s' "$XCAT_AUTHORIZED_KEY_BASE64" | base64 -d > "$1" || return 1
    awk 'NF && !/^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+\/=]+( .*)?$/ {exit 1}
        NF {found=1} END {if (!found) exit 1}' "$1" || return 1
    ssh-keygen -l -f "$1" >/dev/null
}

xcat_write_installer()
{
    printf 'DISTRIBUTIONS="base.txz kernel.txz"\nBSDINSTALL_DISTDIR="%s/dist"\nexport nonInteractive="YES"\n' "$XCAT_WORK"
    if [ "$XCAT_FILESYSTEM" = zfs ]; then
        printf 'export ZFSBOOT_DISKS="%s"\nexport ZFSBOOT_VDEV_TYPE="stripe"\n' "$XCAT_TARGET_DISK"
        printf 'export ZFSBOOT_POOL_NAME="zroot"\nexport ZFSBOOT_PARTITION_SCHEME="GPT"\nexport ZFSBOOT_SWAP_SIZE="%s"\n' "$XCAT_SWAP_SIZE"
    elif [ "$XCAT_SWAP_SIZE" = 0 ]; then
        printf 'PARTITIONS="%s GPT { auto freebsd-ufs / }"\n' "$XCAT_TARGET_DISK"
    else
        printf 'PARTITIONS="%s GPT { %s freebsd-swap, auto freebsd-ufs / }"\n' "$XCAT_TARGET_DISK" "$XCAT_SWAP_SIZE"
    fi
    cat "$1"
}

xcat_install_system()
{
    kldload -n zfs && kldload -n geom_eli || return 1
    xcat_check_disk && xcat_scan_labels && xcat_fetch_distributions || return 1
    xcat_write_installer "$1" > "$XCAT_WORK/installerconfig" || return 1
    xcat_status begin && xcat_check_disk || return 1
    for xcat_provider in $XCAT_CLEAR_LABELS; do zpool labelclear -f "$xcat_provider" || return 1; done
    timeout 3600 env -i PATH="$PATH" LC_ALL=C TERM="${TERM:-vt100}" \
        XCAT_MASTER="$XCAT_MASTER" XCAT_PORT="$XCAT_PORT" XCAT_GENERATION="$XCAT_GENERATION" \
        XCAT_ATTEMPT="$XCAT_ATTEMPT" XCAT_HOSTNAME="$XCAT_HOSTNAME" \
        XCAT_PROVISIONING_IF="$XCAT_PROVISIONING_IF" XCAT_IPV4="$XCAT_IPV4" \
        XCAT_NETMASK="$XCAT_NETMASK" XCAT_GATEWAY="$XCAT_GATEWAY" XCAT_NAMESERVERS="$XCAT_NAMESERVERS" \
        XCAT_AUTHORIZED_KEY_BASE64="$XCAT_AUTHORIZED_KEY_BASE64" \
        bsdinstall script "$XCAT_WORK/installerconfig" > "$XCAT_WORK/bsdinstall.log" 2>&1 || return 1
    xcat_status complete
}
