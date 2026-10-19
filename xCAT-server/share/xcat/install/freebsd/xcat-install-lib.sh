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

xcat_netmask()
{
    xcat_ipv4 "$1" || return 1
    printf '%s\n' "$1" | awk -F. '{for(i=1;i<=4;i++) {
        if (partial && $i != 0) exit 1
        if ($i !~ /^(255|254|252|248|240|224|192|128|0)$/) exit 1
        if ($i != 255) partial=1
    }}'
}

xcat_boot_options()
{
    [ -n "$1" ] || return 0
    [ "${#1}" -le 21848 ] || return 1
    case "$1" in *[!A-Za-z0-9+/=]*) return 1 ;; esac
    xcat_options=$(printf '%s' "$1" | base64 -d) || return 1
    [ "${#xcat_options}" -lt 16384 ] || return 1
    [ "$(printf '%s\n' "$xcat_options" | base64 | tr -d '\n')" = "$1" ] || return 1
    printf '%s\n' "$xcat_options" | LC_ALL=C awk '
        BEGIN {
            split("exec loader_conf_files loader_conf_dirs local_loader_conf_files product_vars nextboot_conf nextboot_enable kernel kernels kernels_autodetect kernel_options kernel_path kernelname xen_kernel bootfile module_path module_blacklist lua_path loader_path efi-version currdev loaddev root rootdev rootpath root_path rootflags rootfstype root_disk_unit num_ide_disks init initrd rdinit console boot_serial boot_multicons boot_multiple boot_mute boot_mutemsgs boot_askname boot_cdrom boot_dfltroot autoboot_delay beastie_disable hostname hostid hostuuid ip bootif netmask gateway nameserver nameservers kern.hostname kern.hostid kern.hostuuid kern.domainname kern.bootfile kern.maxphys", names, " ")
            for (i in names) reserved[names[i]]=1
        }
        {
            if (NR > 128 || $0 !~ /^[A-Za-z][A-Za-z0-9_.-]*="[A-Za-z0-9_.,:+\/@%=\-]*"$/) exit 1
            key=substr($0,1,index($0,"=")-1)
            value=substr($0,length(key)+3,length($0)-length(key)-3)
            if (length(key)>128 || length(value)>128 || key<=previous) exit 1
            previous=key; name=tolower(key)
            if (reserved[name] || name=="kern.geom.label.gpt.enable" || name ~ /^(xcat[_.]|mdroot[_.]|kernel_)/ ||
                name ~ /^mfs(bsd|root)?([_.]|$)/ || name ~ /^(boot\.|dhcp\.|init_|hostuuid_|bootenv|zfs_be_)/ ||
                name ~ /^(vfs\.root[._]|vfs\.zfs\.(boot|root))/ ||
                name ~ /^(comconsole_|hw\.uart\.console(\.|$))/ || name ~ /^hint\.(uart|sio)\./ ||
                name ~ /_(before|after|error|name|type)$/) exit 1
            if ((key ~ /_load$/ || key ~ /^boot_(ddb|gdb|pause|single|verbose|safe)$/) && value !~ /^(YES|NO)$/) exit 1
            print
        }'
}

xcat_console_settings()
{
    case "$XCAT_CONSOLE_FLOW" in none|hard) ;; *) return 1 ;; esac
    case "$XCAT_CONSOLE_PORT" in
        none) [ "$XCAT_CONSOLE_SPEED" = 0 ] && [ "$XCAT_CONSOLE_FLOW" = none ]; return ;;
        0) xcat_console_io=0x3f8 ;;
        1) xcat_console_io=0x2f8 ;;
        2) xcat_console_io=0x3e8 ;;
        3) xcat_console_io=0x2e8 ;;
        *) return 1 ;;
    esac
    case "$XCAT_CONSOLE_SPEED" in 9600|19200|38400|57600|115200) ;; *) return 1 ;; esac
    printf 'comconsole_port="%s"\ncomconsole_speed="%s"\n' "$xcat_console_io" "$XCAT_CONSOLE_SPEED"
    printf '%s\n' 'console="comconsole,${console}"' 'boot_serial="YES"' 'boot_multicons="YES"'
    printf 'hw.uart.console="io:%s,br:%s"\n' "$xcat_console_io" "$XCAT_CONSOLE_SPEED"
    printf 'hint.uart.%s.at="acpi"\nhint.uart.%s.port="%s"\n' \
        "$XCAT_CONSOLE_PORT" "$XCAT_CONSOLE_PORT" "$xcat_console_io"
}

xcat_bootstrap_network()
{
    if [ -n "$(kenv -q xcat_network_chunks || :)" ]; then
        . /usr/local/libexec/xcat-network.sh
        xcat_network_bootstrap || return 1
    fi
    XCAT_BOOTSTRAP_MODE=$(kenv -q xcat_bootstrap || :)
    XCAT_BOOTSTRAP_MODE=${XCAT_BOOTSTRAP_MODE:-dhcp}
    case "$XCAT_BOOTSTRAP_MODE" in
        dhcp) dhclient "$XCAT_PROVISIONING_IF" ;;
        static)
            XCAT_BOOTSTRAP_IPV4=$(kenv -q xcat_bootstrap_ipv4) &&
                XCAT_BOOTSTRAP_NETMASK=$(kenv -q xcat_bootstrap_netmask) || return 1
            XCAT_BOOTSTRAP_GATEWAY=$(kenv -q xcat_bootstrap_gateway || :)
            xcat_ipv4 "$XCAT_BOOTSTRAP_IPV4" && xcat_netmask "$XCAT_BOOTSTRAP_NETMASK" || return 1
            [ -z "$XCAT_BOOTSTRAP_GATEWAY" ] || xcat_ipv4 "$XCAT_BOOTSTRAP_GATEWAY" || return 1
            ifconfig "$XCAT_PROVISIONING_IF" inet "$XCAT_BOOTSTRAP_IPV4" netmask "$XCAT_BOOTSTRAP_NETMASK" up || return 1
            [ -z "$XCAT_BOOTSTRAP_GATEWAY" ] || route add default "$XCAT_BOOTSTRAP_GATEWAY"
            ;;
        *) xcat_error 'Invalid bootstrap network mode'; return 1 ;;
    esac
}

xcat_check_bootstrap()
{
    if [ -n "${XCAT_BOOTSTRAP_NETWORK_BASE64:-}${XCAT_BOOT_NETWORK_BASE64:-}" ]; then
        . /usr/local/libexec/xcat-network.sh
        xcat_network_check || return 1
    fi
    case "$XCAT_FORMAT" in xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6) ;; *) return 0 ;; esac
    [ "$XCAT_BOOTSTRAP" = "$XCAT_BOOTSTRAP_MODE" ] || return 1
    [ "$XCAT_BOOTSTRAP" = static ] || return 0
    [ "$XCAT_IPV4" = "$XCAT_BOOTSTRAP_IPV4" ] && [ "$XCAT_NETMASK" = "$XCAT_BOOTSTRAP_NETMASK" ] &&
        [ "$XCAT_GATEWAY" = "$XCAT_BOOTSTRAP_GATEWAY" ]
}

xcat_fetch_config()
{
    if [ -z "${XCAT_BOOT_NETWORK_BASE64:-}" ]; then
        fetch -T 60 -o "$XCAT_WORK/config" "$1"
        return
    fi
    # LACP negotiation and bridge forwarding can finish after address setup.
    xcat_fetch_started=$(date +%s)
    xcat_fetch_attempt=0
    while [ "$xcat_fetch_attempt" -lt 120 ]; do
        xcat_fetch_now=$(date +%s)
        xcat_fetch_wait=$((120 - xcat_fetch_now + xcat_fetch_started))
        [ "$xcat_fetch_wait" -gt 0 ] || break
        [ "$xcat_fetch_wait" -le 10 ] || xcat_fetch_wait=10
        if fetch -T "$xcat_fetch_wait" -o "$XCAT_WORK/config" "$1"; then
            return 0
        fi
        rm -f "$XCAT_WORK/config" || return 1
        xcat_fetch_attempt=$((xcat_fetch_attempt + 1))
        sleep 1
    done
    xcat_error 'Cannot download the installation configuration after network setup'
}

xcat_guarded_storage()
{
    case "$XCAT_FORMAT" in xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6) return 0 ;; *) return 1 ;; esac
}

xcat_extended_storage()
{
    case "$XCAT_FORMAT" in xcat-freebsd-install-5|xcat-freebsd-install-6) return 0 ;; *) return 1 ;; esac
}

xcat_zfs_members()
{
    [ "$XCAT_FILESYSTEM" = zfs ] && [ "$XCAT_SWAP_SIZE" = 0 ] &&
        [ "$XCAT_SWAP_MODE" = none ] || return 1
    case "$XCAT_ZFS_TOPOLOGY" in
        stripe) xcat_extended_storage || return 1 ;;
        mirror|raid10|raidz1|raidz2|raidz3) ;;
        *) return 1 ;;
    esac
    printf '%s\n' "$XCAT_ZFS_VDEVS" | LC_ALL=C awk -v topology="$XCAT_ZFS_TOPOLOGY" '
        NR != 1 || length($0) > 4096 {bad=1; next}
        {
            groups=split($0, group, ";")
            for (g=1; g<=groups; g++) {
                members=split(group[g], member, ",")
                if (!length(group[g]) || !members || (topology == "raid10" && members != 2)) bad=1
                for (m=1; m<=members; m++) {
                    if (split(member[m], pair, "@") != 2) {bad=1; continue}
                    device=pair[1]; serial=pair[2]; number=device
                    sub(/^[a-z]+/, "", number)
                    if (device !~ /^(ada|da|nda|nvd|vtbd)(0|[1-9][0-9]*)$/ || length(number)>5 ||
                        serial !~ /^[A-Za-z0-9_.:+-]+$/ || length(serial)>128) bad=1
                    if (devices[device]++ || serials[serial]++) bad=1
                    record[++count]=device "\t" serial "\t" g
                }
            }
        }
        END {
            minimum=(topology == "stripe" ? 1 : topology == "mirror" ? 2 : topology == "raidz1" ? 3 : topology == "raidz3" ? 5 : 4)
            if (NR != 1 || bad || count<minimum || count>16 ||
                (topology == "stripe" && count!=1) ||
                (topology == "raid10" ? groups<2 : groups!=1)) exit 1
            for (i=1; i<=count; i++) print record[i]
        }'
}

xcat_zfs_primary()
(
    [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ] && xcat_hex "$XCAT_GENERATION" 32 || exit 1
    xcat_primary=$(xcat_zfs_members) || exit 1
    printf '%s\n' "$xcat_primary" | awk -F '\t' -v generation="$XCAT_GENERATION" \
        -v topology="$XCAT_ZFS_TOPOLOGY" -v output="${1:-arguments}" '
        BEGIN {if(output!="arguments" && output!="status") exit 1; if(output=="status") print "zroot"}
        $3!=group {
            group=$3
            if(topology=="raid10" || (output=="status" && topology!="stripe"))
                print (topology=="raid10" ? "mirror" : topology)
        }
        {print "/dev/gpt/z" generation (NR-1)}'
)

xcat_zfs_auxiliary()
(
    [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ] || exit 0
    xcat_hex "$XCAT_GENERATION" 32 || exit 1
    xcat_primary=$(xcat_zfs_members) || exit 1
    printf '%s\n' "$xcat_primary" | XCAT_AUX_SPECIAL="$XCAT_ZFS_SPECIAL_VDEVS" \
        XCAT_AUX_LOG="$XCAT_ZFS_LOG_VDEVS" XCAT_AUX_CACHE="$XCAT_ZFS_CACHE_VDEVS" \
        XCAT_AUX_SMALL="$XCAT_ZFS_SPECIAL_SMALL_BLOCKS" LC_ALL=C awk \
        -v topology="$XCAT_ZFS_TOPOLOGY" -v generation="$XCAT_GENERATION" -v output="${1:-members}" '
        function emit(role, group, kind, names,    n, list, i, p) {
            n=split(names,list,",")
            if (output=="arguments" && kind=="mirror") print "mirror"
            if (output=="status" && kind=="mirror") print "mirror"
            for(i=1;i<=n;i++) {
                split(list[i],p,"@")
                if(output=="members") print p[1] "\t" p[2] "\t" role ":" group
                else if(output=="partitions") print p[1] "\t" p[2] "\t" role ":" group "\ta" generation ordinal
                else print "/dev/gpt/a" generation ordinal
                ordinal++
            }
        }
        {devices[$1]=1; serials[$2]=1; primary++}
        END {
            size=ENVIRON["XCAT_AUX_SMALL"]
            if(size !~ /^(0|[1-9][0-9]*)$/ || length(size)>8 || size+0>16777216 || (size+0>0 && size+0<512)) exit 1
            n=size+0; while(n>1 && n%2==0) n/=2
            if(n>1 || (size+0>0 && ENVIRON["XCAT_AUX_SPECIAL"]=="-")) exit 1
            split("special log cache",roles," ")
            total=primary
            for(r=1;r<=3;r++) {
                role=roles[r]; text=ENVIRON["XCAT_AUX_" toupper(role)]
                if(text=="-") continue
                if(!length(text) || length(text)>16384 || (role=="special" && topology=="stripe")) exit 1
                groups[role]=split(text,lists,";")
                if(role=="cache" && groups[role]!=1) exit 1
                width=(topology=="mirror" ? primary : topology=="raidz2" ? 3 : topology=="raidz3" ? 4 : 2)
                for(g=1;g<=groups[role];g++) {
                    count=split(lists[g],members,",")
                    if(!length(lists[g]) || count<1 || (role=="special" && count!=width)) exit 1
                    kind[role,g]=(role=="special" || (role=="log" && count>1) ? "mirror" : "stripe")
                    names[role,g]=lists[g]
                    for(i=1;i<=count;i++) {
                        if(split(members[i],p,"@")!=2 || p[1]!~/^(ada|da|nda|nvd|vtbd)(0|[1-9][0-9]{0,4})$/ ||
                            p[2]!~/^[A-Za-z0-9_.:+-]+$/ || length(p[2])>128 || devices[p[1]]++ || serials[p[2]]++ || ++total>128) exit 1
                    }
                }
            }
            if(output!="members" && output!="arguments" && output!="status" && output!="partitions") exit 1
            ordinal=0
            for(r=1;r<=3;r++) {
                role=roles[r]
                if(!groups[role]) continue
                if(output=="arguments") print role
                if(output=="status") print (role=="log" ? "logs" : role)
                if(role=="log")
                    for(g=1;g<=groups[role];g++) if(kind[role,g]=="stripe") emit(role,g,kind[role,g],names[role,g])
                for(g=1;g<=groups[role];g++)
                    if(role!="log" || kind[role,g]!="stripe") emit(role,g,kind[role,g],names[role,g])
            }
        }'
)

xcat_zfs_all_members()
(
    xcat_primary=$(xcat_zfs_members) && xcat_auxiliary=$(xcat_zfs_auxiliary) || exit 1
    printf '%s\n' "$xcat_primary"
    [ -z "$xcat_auxiliary" ] || printf '%s\n' "$xcat_auxiliary"
    exit 0
)

xcat_zfs_dataset_plan()
(
    [ -n "${XCAT_ZFS_DATASETS_BASE64:-}" ] && [ "${#XCAT_ZFS_DATASETS_BASE64}" -le 16384 ] || exit 1
    case "$XCAT_ZFS_DATASETS_BASE64" in *[!A-Za-z0-9+/=]*) exit 1 ;; esac
    xcat_declaration=$(printf '%s' "$XCAT_ZFS_DATASETS_BASE64" | base64 -d) || exit 1
    [ "$(printf '%s\n' "$xcat_declaration" | base64 | tr -d '\n')" = "$XCAT_ZFS_DATASETS_BASE64" ] || exit 1
    printf '%s\n' "$xcat_declaration" | awk -v expected_kind=os -v expected_pool=zroot \
        -f "${1:-/usr/local/libexec/configzfs-datasets.awk}"
)

xcat_verify_datasets()
(
    xcat_dataset_kind=$1 xcat_dataset_pool=$2 xcat_dataset_altroot=${3:-}
    xcat_pool_encryption_root=-
    if [ "$xcat_dataset_kind" = data ]; then
        xcat_pool_encryption_root=$(zfs get -H -o value encryptionroot "$xcat_dataset_pool") || exit 1
    fi
    while IFS="$(printf '\t')" read -r xcat_dataset xcat_properties; do
        [ "$(zfs get -H -o value type "$xcat_dataset")" = filesystem ] || exit 1
        xcat_encryption_root=$(zfs get -H -o value encryptionroot "$xcat_dataset") || exit 1
        [ "$xcat_encryption_root" = "$xcat_pool_encryption_root" ] || exit 1
        xcat_old_ifs=$IFS IFS=,
        set -f
        set -- $xcat_properties
        IFS=$xcat_old_ifs
        for xcat_property do
            xcat_key=${xcat_property%%=*} xcat_expected=${xcat_property#*=}
            xcat_actual=$(zfs get -Hp -o value "$xcat_key" "$xcat_dataset") || exit 1
            case "$xcat_key:$xcat_expected" in
                mountpoint:/*) xcat_expected=$xcat_dataset_altroot$xcat_expected
                    [ "$xcat_expected" = / ] || xcat_expected=${xcat_expected%/} ;;
                quota:none|refquota:none|reservation:none|refreservation:none)
                    [ "$xcat_actual" != 0 ] || xcat_actual=none ;;
                compression:zstd|compression:zstd-3)
                    [ "$xcat_actual" != zstd ] || xcat_actual=zstd-3
                    xcat_expected=zstd-3 ;;
            esac
            if [ "$xcat_dataset_kind:$xcat_dataset:$xcat_key" = os:zroot/ROOT/default:canmount ]; then
                xcat_expected=noauto
            fi
            [ "$xcat_actual" = "$xcat_expected" ] || exit 1
        done
    done
)

xcat_read_config()
{
    XCAT_FORMAT= XCAT_RELEASE= XCAT_NODE= XCAT_GENERATION= XCAT_MASTER= XCAT_PORT=
    XCAT_MAC= XCAT_IPV4= XCAT_NETMASK= XCAT_GATEWAY= XCAT_HOSTNAME=
    XCAT_TARGET_DISK= XCAT_TARGET_DISK_IDENT= XCAT_FILESYSTEM= XCAT_SWAP_SIZE=
    XCAT_ZFS_TOPOLOGY= XCAT_ZFS_VDEVS= XCAT_SWAP_MODE=
    XCAT_ZFS_COMPRESSION= XCAT_ZFS_ASHIFT= XCAT_DISK_ACTION= XCAT_PRESERVE_DISKS=
    XCAT_ZFS_LOG_VDEVS= XCAT_ZFS_CACHE_VDEVS= XCAT_ZFS_SPECIAL_VDEVS= XCAT_ZFS_SPECIAL_SMALL_BLOCKS=
    XCAT_DIST_URL= XCAT_BASE_SHA256= XCAT_KERNEL_SHA256= XCAT_AUTHORIZED_KEY_BASE64=
    XCAT_INSTALL_URL= XCAT_PACKAGE_PLAN_SHA256= XCAT_BOOT_MEDIA_SHA256= XCAT_RUNTIME_SHA256=
    XCAT_BOOTSTRAP= XCAT_CONSOLE_PORT= XCAT_CONSOLE_SPEED= XCAT_CONSOLE_FLOW=
    XCAT_BOOTSTRAP_NETWORK_BASE64= XCAT_ZFS_DATASETS_BASE64= XCAT_ZFS_DATASET_PLAN=
    XCAT_INSTALL_BOOT_OPTIONS_BASE64= XCAT_TARGET_BOOT_OPTIONS_BASE64=
    XCAT_NAMESERVERS= xcat_seen=' '
    [ -f "$1" ] || return 1
    xcat_config_size=$(wc -c < "$1") || return 1
    [ "$xcat_config_size" -gt 0 ] && [ "$xcat_config_size" -le 32768 ] || return 1
    xcat_read_bytes=0 xcat_unterminated=0 xcat_skipped=0
    while IFS= read -r xcat_line || { [ -n "$xcat_line" ] && xcat_unterminated=1; }; do
        xcat_read_bytes=$((xcat_read_bytes + ${#xcat_line} + 1 - xcat_unterminated))
        [ "$xcat_read_bytes" -le 32768 ] || return 1
        case "$xcat_line" in ''|'#'*) xcat_skipped=1; continue ;; *=*) ;; *) xcat_error 'Malformed configuration'; return 1 ;; esac
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
            zfs_topology) XCAT_ZFS_TOPOLOGY=$xcat_value ;;
            zfs_vdevs) XCAT_ZFS_VDEVS=$xcat_value ;;
            swap_mode) XCAT_SWAP_MODE=$xcat_value ;;
            zfs_compression) XCAT_ZFS_COMPRESSION=$xcat_value ;;
            zfs_ashift) XCAT_ZFS_ASHIFT=$xcat_value ;;
            disk_action) XCAT_DISK_ACTION=$xcat_value ;;
            preserve_disks) XCAT_PRESERVE_DISKS=$xcat_value ;;
            zfs_log_vdevs) XCAT_ZFS_LOG_VDEVS=$xcat_value ;;
            zfs_cache_vdevs) XCAT_ZFS_CACHE_VDEVS=$xcat_value ;;
            zfs_special_vdevs) XCAT_ZFS_SPECIAL_VDEVS=$xcat_value ;;
            zfs_special_small_blocks) XCAT_ZFS_SPECIAL_SMALL_BLOCKS=$xcat_value ;;
            dist_url) XCAT_DIST_URL=$xcat_value ;;
            base_sha256) XCAT_BASE_SHA256=$xcat_value ;;
            kernel_sha256) XCAT_KERNEL_SHA256=$xcat_value ;;
            install_url) XCAT_INSTALL_URL=$xcat_value ;;
            package_plan_sha256) XCAT_PACKAGE_PLAN_SHA256=$xcat_value ;;
            boot_media_sha256) XCAT_BOOT_MEDIA_SHA256=$xcat_value ;;
            runtime_sha256) XCAT_RUNTIME_SHA256=$xcat_value ;;
            authorized_key_base64) XCAT_AUTHORIZED_KEY_BASE64=$xcat_value ;;
            nameservers) XCAT_NAMESERVERS=$xcat_value ;;
            bootstrap) XCAT_BOOTSTRAP=$xcat_value ;;
            bootstrap_network_base64) XCAT_BOOTSTRAP_NETWORK_BASE64=$xcat_value ;;
            zfs_datasets_base64) XCAT_ZFS_DATASETS_BASE64=$xcat_value ;;
            console_port) XCAT_CONSOLE_PORT=$xcat_value ;;
            console_speed) XCAT_CONSOLE_SPEED=$xcat_value ;;
            console_flow) XCAT_CONSOLE_FLOW=$xcat_value ;;
            install_boot_options_base64) XCAT_INSTALL_BOOT_OPTIONS_BASE64=$xcat_value ;;
            target_boot_options_base64) XCAT_TARGET_BOOT_OPTIONS_BASE64=$xcat_value ;;
            *) xcat_error "Unknown field: $xcat_key"; return 1 ;;
        esac
    done < "$1"
    [ "$XCAT_RELEASE" = 15.1-RELEASE ] || return 1
    case "$xcat_seen" in *' zfs_datasets_base64 '*)
        xcat_guarded_storage && [ "$XCAT_FILESYSTEM" = zfs ] || return 1
        XCAT_ZFS_DATASET_PLAN=$(xcat_zfs_dataset_plan) || return 1 ;;
    esac
    case "$xcat_seen" in *' bootstrap_network_base64 '*)
        case "$XCAT_FORMAT" in xcat-freebsd-install-[3456]) ;; *) return 1 ;; esac
        [ -n "$XCAT_BOOTSTRAP_NETWORK_BASE64" ] && [ "${#XCAT_BOOTSTRAP_NETWORK_BASE64}" -le 8192 ] || return 1
        case "$XCAT_BOOTSTRAP_NETWORK_BASE64" in *[!A-Za-z0-9+/=]*) return 1 ;; esac ;;
    esac
    if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
        for xcat_required in zfs_log_vdevs zfs_cache_vdevs zfs_special_vdevs zfs_special_small_blocks; do
            case "$xcat_seen" in *" $xcat_required "*) ;; *) return 1 ;; esac
        done
        xcat_zfs_auxiliary >/dev/null || return 1
    else
        case "$xcat_seen" in
            *' zfs_log_vdevs '*|*' zfs_cache_vdevs '*|*' zfs_special_vdevs '*|*' zfs_special_small_blocks '*) return 1 ;;
        esac
    fi
    if xcat_extended_storage; then
        for xcat_required in zfs_compression zfs_ashift disk_action preserve_disks; do
            case "$xcat_seen" in *" $xcat_required "*) ;; *) return 1 ;; esac
        done
        printf '%s\n' "$XCAT_ZFS_COMPRESSION" | awk '!/^(off|lz4|gzip(-[1-9])?|zstd(-([1-9]|1[0-9]))?)$/ {exit 1}' || return 1
        [ "$XCAT_ZFS_COMPRESSION" != gzip-6 ] || XCAT_ZFS_COMPRESSION=gzip
        case "$XCAT_ZFS_ASHIFT" in 9|10|11|12|13|14|15|16) ;; *) return 1 ;; esac
        case "$XCAT_DISK_ACTION" in empty|erase) ;; *) return 1 ;; esac
        xcat_preserved_members >/dev/null || return 1
    else
        case "$xcat_seen" in *' zfs_compression '*|*' zfs_ashift '*|*' disk_action '*|*' preserve_disks '*) return 1 ;; esac
    fi
    if [ "$XCAT_FORMAT" = xcat-freebsd-install-3 ] || xcat_guarded_storage; then
        for xcat_required in bootstrap console_port console_speed console_flow install_boot_options_base64 target_boot_options_base64; do
            case "$xcat_seen" in *" $xcat_required "*) ;; *) return 1 ;; esac
        done
        case "$XCAT_BOOTSTRAP" in dhcp|static) ;; *) return 1 ;; esac
        xcat_console_settings >/dev/null && xcat_boot_options "$XCAT_INSTALL_BOOT_OPTIONS_BASE64" >/dev/null &&
            xcat_boot_options "$XCAT_TARGET_BOOT_OPTIONS_BASE64" >/dev/null || return 1
    else
        case "$xcat_seen" in
            *' bootstrap '*|*' console_port '*|*' console_speed '*|*' console_flow '*|*' install_boot_options_base64 '*|*' target_boot_options_base64 '*) return 1 ;;
        esac
    fi
    case "$XCAT_FORMAT" in
        xcat-freebsd-install-1)
            case "$xcat_seen" in
                *' install_url '*|*' package_plan_sha256 '*|*' boot_media_sha256 '*|*' runtime_sha256 '*) return 1 ;;
            esac
            xcat_hex "$XCAT_BASE_SHA256" 64 && xcat_hex "$XCAT_KERNEL_SHA256" 64 || return 1
            xcat_url "$XCAT_DIST_URL" || return 1
            ;;
        xcat-freebsd-install-2|xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6)
            [ "$xcat_read_bytes" -eq "$xcat_config_size" ] && [ "$xcat_unterminated" -eq 0 ] &&
                [ "$xcat_skipped" -eq 0 ] || return 1
            LC_ALL=C awk '/[^ -~]/ {exit 1}' "$1" || return 1
            case "$xcat_seen" in *' dist_url '*|*' base_sha256 '*|*' kernel_sha256 '*) return 1 ;; esac
            xcat_disk_fields='target_disk target_disk_ident'
            if xcat_guarded_storage; then
                xcat_disk_fields='zfs_topology zfs_vdevs swap_mode'
                case "$xcat_seen" in *' target_disk '*|*' target_disk_ident '*) return 1 ;; esac
            fi
            for xcat_required in format release node generation master port mac ipv4 netmask gateway hostname \
                $xcat_disk_fields filesystem swap_size install_url package_plan_sha256 \
                boot_media_sha256 runtime_sha256 authorized_key_base64 nameservers; do
                case "$xcat_seen" in *" $xcat_required "*) ;; *) return 1 ;; esac
            done
            xcat_hex "$XCAT_PACKAGE_PLAN_SHA256" 64 && xcat_hex "$XCAT_BOOT_MEDIA_SHA256" 64 &&
                xcat_hex "$XCAT_RUNTIME_SHA256" 64 || return 1
            xcat_url "$XCAT_INSTALL_URL" || return 1
            [ "${#XCAT_NODE}" -le 247 ] && [ "${#XCAT_HOSTNAME}" -le 247 ] || return 1
            ;;
        *) return 1 ;;
    esac
    for xcat_name in "$XCAT_NODE" "$XCAT_HOSTNAME"; do
        case "$xcat_name" in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;; esac
    done
    xcat_hex "$XCAT_GENERATION" 32 || return 1
    for xcat_address in "$XCAT_MASTER" "$XCAT_IPV4" "$XCAT_NETMASK"; do xcat_ipv4 "$xcat_address" || return 1; done
    xcat_netmask "$XCAT_NETMASK" || return 1
    [ -z "$XCAT_GATEWAY" ] || xcat_ipv4 "$XCAT_GATEWAY" || return 1
    case "$XCAT_PORT" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#XCAT_PORT}" -le 5 ] && [ "$XCAT_PORT" -gt 0 ] && [ "$XCAT_PORT" -le 65535 ] || return 1
    printf '%s\n' "$XCAT_MAC" | awk '!/^[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$/ {exit 1}' || return 1
    if xcat_guarded_storage; then
        xcat_zfs_members >/dev/null || return 1
    else
        case "$xcat_seen" in *' zfs_topology '*|*' zfs_vdevs '*|*' swap_mode '*) return 1 ;; esac
        printf '%s\n' "$XCAT_TARGET_DISK" | awk '!/^(ada|da|nda|nvd|vtbd)[0-9]+$/ {exit 1}' || return 1
        case "$XCAT_TARGET_DISK_IDENT" in ''|*[!A-Za-z0-9_.:+-]*) return 1 ;; esac
    fi
    case "$XCAT_FILESYSTEM" in ufs|zfs) ;; *) return 1 ;; esac
    printf '%s\n' "$XCAT_SWAP_SIZE" | awk '!/^(0|[1-9][0-9]*[mMgG])$/ || length($0)>6 {exit 1}' || return 1
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
    [ -n "$xcat_mac" ] || { xcat_error 'Provisioning MAC is missing'; return 1; }
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
    xcat_started=$(date +%s) || return 1
    xcat_retry=0
    while [ "$xcat_retry" -lt 180 ]; do
        xcat_now=$(date +%s) || return 1
        [ "$xcat_now" -ge "$xcat_started" ] && [ "$((xcat_now - xcat_started))" -lt 900 ] || break
        xcat_wait=$((900 - xcat_now + xcat_started))
        [ "$xcat_wait" -le 65 ] || xcat_wait=65
        xcat_response=$(printf 'freebsd-install-v1 %s %s %s\n' "$XCAT_GENERATION" "$XCAT_ATTEMPT" "$xcat_phase" |
            nc -w "$xcat_wait" "$XCAT_MASTER" "$XCAT_PORT") &&
            [ "$xcat_response" = "$(printf 'ready\nfreebsd-install-v1 %s %s ok' "$XCAT_GENERATION" "$xcat_phase")" ] && return 0
        xcat_retry=$((xcat_retry + 1))
        sleep 5
    done
    xcat_error "Controller did not acknowledge $xcat_phase"
}

xcat_preserved_members()
{
    printf '%s\n' "$XCAT_PRESERVE_DISKS" | LC_ALL=C awk -v os="$XCAT_ZFS_VDEVS,${XCAT_ZFS_LOG_VDEVS:--},${XCAT_ZFS_CACHE_VDEVS:--},${XCAT_ZFS_SPECIAL_VDEVS:--}" '
        BEGIN {
            n=split(os,a,/[,;]/)
            for(i=1;i<=n;i++) {if(a[i]=="-") continue; split(a[i],p,"@"); devices[p[1]]=1; serials[p[2]]=1}
        }
        $0 == "-" {next}
        {
            n=split($0,a,",")
            if (NR!=1 || n<1 || n>128) exit 1
            for(i=1;i<=n;i++) {
                if (split(a[i],p,"@")!=2 || p[1]!~/^(ada|da|nda|nvd|vtbd)(0|[1-9][0-9]{0,4})$/ ||
                    p[2]!~/^[A-Za-z0-9_.:+-]+$/ || length(p[2])>128 || devices[p[1]]++ || serials[p[2]]++) exit 1
                print p[1] "\t" p[2] "\t1"
            }
        }
        END {if (NR!=1) exit 1}'
}

xcat_zfs_disk_inventory()
(
    xcat_guarded_storage || exit 1
    xcat_members=$(xcat_zfs_all_members) || exit 1
    xcat_minimum=4294967296
    [ "$XCAT_FORMAT" != xcat-freebsd-install-6 ] || xcat_minimum=134217728
    xcat_inventory=$(xcat_disk_inventory "$xcat_members" "$xcat_minimum") || exit 1
    printf '%s\n' "$xcat_inventory" | awk -F '\t' '$3 ~ /^[0-9]+$/ && $4 < 4294967296 {exit 1}' || exit 1
    if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
        # Pool creation does not force mismatched groups. Check before erase.
        printf '%s\n' "$xcat_inventory" | awk -F '\t' '
            $3 !~ /^cache:/ {
                if (($3 in size) && size[$3] != $4) exit 1
                size[$3]=$4
            }' || {
                xcat_error 'ZFS members in each primary, special or log group must have equal capacities'
                exit 1
            }
    fi
    if xcat_extended_storage; then
        printf '%s\n' "$xcat_inventory" | awk -F '\t' -v ashift="$XCAT_ZFS_ASHIFT" '2^ashift < $5 {exit 1}' || {
            xcat_error 'ZFS ashift is smaller than a selected disk sector'; exit 1
        }
    fi
    printf '%s\n' "$xcat_inventory"
)

xcat_preserved_inventory()
(
    xcat_extended_storage || exit 0
    xcat_members=$(xcat_preserved_members) || exit 1
    [ -n "$xcat_members" ] || exit 0
    xcat_disk_inventory "$xcat_members"
)

xcat_disk_inventory()
(
    xcat_members=$1
    [ -n "$xcat_members" ] || exit 1
    xcat_disks=$(sysctl -n kern.disks) || exit 1
    xcat_disk_info=$(geom disk list) || exit 1
    xcat_inventory=$(printf '%s\n' "$xcat_disk_info" |
        XCAT_STORAGE_MEMBERS="$xcat_members" XCAT_STORAGE_DISKS="$xcat_disks" awk -v minimum="${2:-1048576}" '
        BEGIN {
            members=ENVIRON["XCAT_STORAGE_MEMBERS"]; disks=ENVIRON["XCAT_STORAGE_DISKS"]
            count=split(members, rows, "\n")
            for (i=1; i<=count; i++) {
                split(rows[i], fields, "\t")
                device[i]=fields[1]; serial[fields[1]]=fields[2]
            }
            n=split(disks, names, " ")
            for (i=1; i<=n; i++) present[names[i]]++
        }
        $1 == "Geom" && $2 == "name:" {name=$3; geoms[name]++}
        $2 == "Name:" {providers[name]++; if ($3 != name) bad[name]=1}
        $1 == "ident:" {
            identities[$2]++; ident[name]=$2; id_count[name]++
            if (NF != 2) bad[name]=1
        }
        $1 == "Mediasize:" {size[name]=$2; sizes[name]++}
        $1 == "Sectorsize:" {sector[name]=$2; sectors[name]++}
        $1 == "Mode:" {mode[name]=$2; modes[name]++}
        END {
            for (i=1; i<=count; i++) {
                d=device[i]
                if (present[d] != 1 || geoms[d] != 1 || providers[d] != 1 || bad[d] ||
                    id_count[d] != 1 || ident[d] != serial[d] || identities[serial[d]] != 1 ||
                    sizes[d] != 1 || sectors[d] != 1 || modes[d] != 1 ||
                    size[d] !~ /^[1-9][0-9]*$/ || length(size[d]) > 16 ||
                    size[d]+0 > 9007199254740991 || size[d]+0 < minimum ||
                    sector[d] !~ /^(512|4096)$/ || size[d] % sector[d] ||
                    mode[d] !~ /^r[0-9]+w[0-9]+e[0-9]+$/) exit 1
                output=output rows[i] "\t" size[d] "\t" sector[d] "\t" mode[d] "\n"
            }
            printf "%s", output
        }') || { xcat_error 'Cannot identify the complete ZFS disk set'; exit 1; }
    xcat_snapshot=
    xcat_device_ids=' '
    while IFS="$(printf '\t')" read -r xcat_disk xcat_serial xcat_group xcat_size xcat_sector xcat_mode; do
        xcat_device_id=$(stat -f '%HT:%r' "/dev/$xcat_disk") || exit 1
        case "$xcat_device_id" in 'Character Device:'*) ;; *) exit 1 ;; esac
        xcat_device_id=${xcat_device_id#*:}
        case "$xcat_device_id" in ''|*[!0-9]*) exit 1 ;; esac
        case "$xcat_device_ids" in *" $xcat_device_id "*) xcat_error 'ZFS disk names resolve to one device'; exit 1 ;; esac
        xcat_device_ids="$xcat_device_ids$xcat_device_id "
        xcat_snapshot="$xcat_snapshot$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' \
            "$xcat_disk" "$xcat_serial" "$xcat_group" "$xcat_size" "$xcat_sector" "$xcat_mode" "$xcat_device_id")
"
    done <<XCAT_ZFS_INVENTORY
$xcat_inventory
XCAT_ZFS_INVENTORY
    printf '%s' "$xcat_snapshot"
)

xcat_zfs_initial_graph()
{
    XCAT_STORAGE_SNAPSHOT="$1" awk '
        BEGIN {
            snapshot=ENVIRON["XCAT_STORAGE_SNAPSHOT"]
            n=split(snapshot, rows, "\n")
            for (i=1; i<=n; i++) {
                if (!length(rows[i])) continue
                split(rows[i], f, "\t")
                wanted[f[1]]=1; serial[f[1]]=f[2]; size[f[1]]=f[4]; sector[f[1]]=f[5]
            }
        }
        NF {
            if (NF < 5 || $1 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9]+$/ ||
                $1 > depth+1 || (!records++ && $1 != 0)) {bad=1; next}
            depth=$1
            if ($1 == 0) {
                root=$3
                if (root in wanted) {
                    seen[root]++
                    if ($2 != "DISK" || $4 != size[root] || $5 != sector[root]) bad=1
                }
            } else if (root in wanted) {
                if ($1 != 1 || $2 != "LABEL" || $3 != "diskid/DISK-" serial[root] ||
                    $4 != size[root] || $5 != sector[root] || NF != 9 ||
                    $6 != "i" || $7 != 0 || $8 != "o" || $9 != 0 || aliases[root]++) bad=1
            }
        }
        END {
            for (d in wanted) if (seen[d] != 1) bad=1
            exit bad
        }'
}

xcat_check_empty_disks()
(
    xcat_snapshot=$1
    xcat_storage_tmp=$(mktemp -d "$XCAT_WORK/storage.XXXXXX") || exit 1
    trap 'rm -rf "$xcat_storage_tmp"' 0
    trap 'exit 1' HUP INT TERM
    dd if=/dev/zero of="$xcat_storage_tmp/zero" bs=1048576 count=1 2>"$xcat_storage_tmp/dd.log" &&
        [ "$(wc -c < "$xcat_storage_tmp/zero")" -eq 1048576 ] || exit 1
    while IFS="$(printf '\t')" read -r xcat_disk xcat_serial xcat_group xcat_size xcat_sector xcat_mode xcat_device_id; do
        case "$xcat_disk" in ''|*[!A-Za-z0-9]*) exit 1 ;; esac
        case "$xcat_sector" in 512|4096) ;; *) exit 1 ;; esac
        case "$xcat_size" in ''|*[!0-9]*) exit 1 ;; esac
        [ "${#xcat_size}" -le 16 ] && [ "$xcat_size" -ge 1048576 ] &&
            [ "$xcat_size" -le 9007199254740991 ] && [ "$((xcat_size % xcat_sector))" -eq 0 ] || exit 1
        for xcat_offset in 0 "$(( (xcat_size - 1048576) / xcat_sector ))"; do
            dd if="/dev/$xcat_disk" of="$xcat_storage_tmp/window" bs="$xcat_sector" \
                skip="$xcat_offset" count="$((1048576 / xcat_sector))" 2>"$xcat_storage_tmp/dd.log" &&
                cmp -s "$xcat_storage_tmp/window" "$xcat_storage_tmp/zero" || {
                    xcat_error "Disk $xcat_disk has metadata or an unreadable boundary"; exit 1
                }
        done
        xcat_fstype_status=0
        xcat_fstype=$(LC_ALL=C fstyp -u "/dev/$xcat_disk" 2>&1) || xcat_fstype_status=$?
        [ "$xcat_fstype_status" -eq 1 ] &&
            [ "$xcat_fstype" = "fstyp: /dev/$xcat_disk: filesystem not recognized" ] || {
                xcat_error "Disk $xcat_disk has a filesystem or cannot be inspected"; exit 1
            }
    done <<XCAT_ZFS_SNAPSHOT
$xcat_snapshot
XCAT_ZFS_SNAPSHOT
)

xcat_check_zfs_initial()
(
    xcat_preserved_inventory >/dev/null || exit 1
    xcat_snapshot=$(xcat_zfs_disk_inventory) || exit 1
    printf '%s\n' "$xcat_snapshot" | awk -F '\t' 'NF != 7 || $6 != "r0w0e0" {exit 1}' || {
        xcat_error 'A selected ZFS disk is in use'; exit 1
    }
    xcat_pools=$(zpool list -H -o name) || exit 1
    [ -z "$xcat_pools" ] || { xcat_error 'Imported ZFS pools prevent installation'; exit 1; }
    xcat_geli=$(geli status -s) || exit 1
    [ -z "$xcat_geli" ] || { xcat_error 'Attached GELI providers prevent installation'; exit 1; }
    xcat_graph=$(sysctl -n kern.geom.conftxt) || exit 1
    printf '%s\n' "$xcat_graph" | xcat_zfs_initial_graph "$xcat_snapshot" || {
        xcat_error 'A selected ZFS disk has an existing layout or provider'; exit 1
    }
    xcat_scan_labels && xcat_check_empty_disks "$xcat_snapshot" || exit 1
    xcat_after=$(xcat_zfs_disk_inventory) || exit 1
    [ "$xcat_after" = "$xcat_snapshot" ] || { xcat_error 'The ZFS disk set changed during preflight'; exit 1; }
    printf '%s\n' "$xcat_snapshot"
)

xcat_check_zfs_reinstall()
(
    xcat_extended_storage && [ "$XCAT_DISK_ACTION" = erase ] || exit 1
    xcat_snapshot=$(xcat_zfs_disk_inventory) || exit 1
    printf '%s\n' "$xcat_snapshot" | awk -F '\t' '$6 != "r0w0e0" {exit 1}' || {
        xcat_error 'An OS disk is in use'; exit 1
    }
    xcat_preserved=$(xcat_preserved_inventory) || exit 1
    xcat_pools=$(zpool list -H -o name) && xcat_geli=$(geli status -s) || exit 1
    [ -z "$xcat_pools$xcat_geli" ] || { xcat_error 'Active storage prevents OS reinstall'; exit 1; }
    xcat_graph=$(sysctl -n kern.geom.conftxt) || exit 1
    printf '%s\n' "$xcat_graph" | XCAT_STORAGE_SNAPSHOT="$xcat_snapshot" awk '
        BEGIN {
            n=split(ENVIRON["XCAT_STORAGE_SNAPSHOT"],rows,"\n")
            for(i=1;i<=n;i++) {split(rows[i],f,"\t"); size[f[1]]=f[4]; sector[f[1]]=f[5]; serial[f[1]]=f[2]}
        }
        $1 == 0 {root=$3; delete parent; if(root in size) {seen[root]++; if($2!="DISK" || $4!=size[root] || $5!=sector[root]) bad=1}; next}
        root in size {
            ancestor=parent[$1-1]; parent[$1]=$3
            if($2=="PART" && (($1==1 && $3 ~ ("^" root "p[1-9][0-9]*$")) ||
                ($1==2 && ancestor=="diskid/DISK-" serial[root] && index($3,ancestor "p")==1 &&
                substr($3,length(ancestor)+2)~/^[1-9][0-9]*$/)) && $4>0 && $4+0<=size[root]+0 && $5==sector[root] &&
                $6=="i" && $8=="o" && $9>0 && $9+$4<=size[root] && $10=="ty" &&
                $11~/^(efi|freebsd-boot|freebsd-zfs|freebsd-ufs|freebsd-swap)$/ && $12=="xs" && $13=="GPT") {
                signature=$4 " " $5 " " $9 " " $11
                key=root SUBSEP $7
                if($1==1) native[key]=signature; else aliases[key]=signature
                part[$3]=$11; next
            }
            if($2=="LABEL" && (($1==1 && $3=="diskid/DISK-" serial[root]) ||
                (($1==2 || $1==3) && ancestor in part &&
                ($3~/^(gpt|gptid)\/[A-Za-z0-9_.+-]+$/ ||
                (part[ancestor]=="freebsd-ufs" && $3~/^(ufs|ufsid)\/[A-Za-z0-9_.+-]+$/) ||
                (part[ancestor]=="efi" && $3~/^msdosfs\/[A-Za-z0-9_.+-]+$/))))) next
            bad=1
        }
        END {
            for(d in size) if(seen[d]!=1) bad=1
            for(k in aliases) if(aliases[k]!=native[k]) bad=1
            exit bad
        }' || {
        xcat_error 'An OS disk has an unsupported provider or partition layout'; exit 1
    }
    xcat_scan_labels || exit 1
    xcat_partitions=$(gpart list) || exit 1
    xcat_selected_tables=$(printf '%s\n' "$xcat_partitions" | XCAT_STORAGE_SNAPSHOT="$xcat_snapshot" awk '
        BEGIN {n=split(ENVIRON["XCAT_STORAGE_SNAPSHOT"],rows,"\n"); for(i=1;i<=n;i++){split(rows[i],f,"\t"); wanted[f[1]]=1}}
        $1=="Geom" && $2=="name:" {selected=($3 in wanted)}
        selected {
            if(($1=="scheme:" && $2!="GPT") || ($1=="state:" && $2!="OK") ||
                ($1=="modified:" && $2!="false") || ($1=="Mode:" && $2!="r0w0e0")) bad=1
            print
        }
        END {exit bad}') || exit 1
    [ "$(xcat_zfs_disk_inventory)" = "$xcat_snapshot" ] &&
        [ "$(xcat_preserved_inventory)" = "$xcat_preserved" ] || exit 1
    printf '%s\n' "$xcat_snapshot"
    printf 'preserved\n%s\npartitions\n%s\nlabels\n%s\n' "$xcat_preserved" "$xcat_selected_tables" "$XCAT_REINSTALL_LABELS"
)

xcat_erase_os_disks()
(
    xcat_before=$(cat "$1") && xcat_now=$(xcat_check_zfs_reinstall) || exit 1
    [ "$xcat_now" = "$xcat_before" ] || { xcat_error 'OS or preserved disk state changed before reinstall'; exit 1; }
    xcat_snapshot=$(xcat_zfs_disk_inventory) && xcat_preserved=$(xcat_preserved_inventory) || exit 1
    xcat_scan_labels || exit 1
    for xcat_provider in $XCAT_CLEAR_LABELS; do zpool labelclear -f "$xcat_provider" >/dev/null || exit 1; done
    while IFS="$(printf '\t')" read -r xcat_disk xcat_serial xcat_group xcat_size xcat_sector xcat_mode xcat_device_id; do
        xcat_identity=$(xcat_zfs_disk_inventory) || exit 1
        [ "$(printf '%s\n' "$xcat_identity" | cut -f1-5,7)" = "$(printf '%s\n' "$xcat_snapshot" | cut -f1-5,7)" ] || exit 1
        xcat_parts=$(gpart show "$xcat_disk" 2>/dev/null) || xcat_parts=
        if [ -n "$xcat_parts" ]; then gpart destroy -F "$xcat_disk" >/dev/null || exit 1; fi
        for xcat_offset in 0 "$(( (xcat_size - 1048576) / xcat_sector ))"; do
            dd if=/dev/zero of="/dev/$xcat_disk" bs="$xcat_sector" seek="$xcat_offset" \
                count="$((1048576 / xcat_sector))" conv=notrunc || exit 1
        done
    done <<XCAT_OS_DISKS
$xcat_snapshot
XCAT_OS_DISKS
    [ "$(xcat_preserved_inventory)" = "$xcat_preserved" ] || exit 1
    xcat_check_zfs_initial
)

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

xcat_zfs_label_owner()
{
    awk '
        function guid(s) {
            return s~/^[1-9][0-9]*$/ && length(s)<=20 && (length(s)<20 || "g" s<="g18446744073709551615")
        }
        /Bad label cksum|failed to read label|failed to unpack label/ {bad=1}
        $0=="L2ARC device header" {header=1; headers++; next}
        $0=="L2ARC device log blocks" {header=0}
        header && $1=="magic:" {if(NF!=2 || "m" $2!="m6504978260106102853") bad=1; magic++}
        header && $1=="version:" {if(NF!=2 || $2!="1") bad=1; version++}
        $1=="name:" {
            if(NF!=2 || (names++ && name!=$2)) bad=1
            name=$2
        }
        !header && $1=="state:" {
            if(NF!=2 || $2!~/^(0|1|4)$/ || (states++ && state!=$2)) bad=1
            state=$2
        }
        $1=="pool_guid:" {
            if(NF!=2 || !guid($2) || (guids++ && "g" owner!="g" $2)) bad=1
            owner=$2
            if(header) cache_guids++
        }
        END {
            if(bad || !states || !guids) exit 1
            if(state==4) {
                if(names || headers!=1 || cache_guids!=1 || magic!=1 || version!=1) exit 1
                print "cache\t" owner
            } else {
                if(!names || headers) exit 1
                print name "\t" owner
            }
        }'
}

xcat_scan_os_label()
{
    xcat_owner=$(printf '%s\n' "$xcat_labels" | xcat_zfs_label_owner) || {
        xcat_error "Cannot establish ZFS ownership on $xcat_provider"; return 1
    }
    xcat_owner_name=$(printf '%s\n' "$xcat_owner" | cut -f1)
    xcat_owner_guid=$(printf '%s\n' "$xcat_owner" | cut -f2)
    case " $xcat_selected " in *" $xcat_disk "*) xcat_is_selected=1 ;; *) xcat_is_selected=0 ;; esac
    if [ "$xcat_is_selected" = 1 ]; then
        [ "$XCAT_DISK_ACTION" = erase ] || { xcat_error 'A selected disk already contains ZFS labels'; return 1; }
        case "$xcat_owner_name" in
            "'zroot'")
                [ -z "$xcat_os_guid" ] || [ "$xcat_os_guid" = "$xcat_owner_guid" ] || {
                    xcat_error 'Selected OS disks belong to different pools'; return 1
                }
                xcat_os_guid=$xcat_owner_guid
                ;;
            cache) xcat_os_cache_guids="$xcat_os_cache_guids $xcat_owner_guid" ;;
            *) xcat_error 'An OS disk contains a data pool'; return 1 ;;
        esac
        XCAT_CLEAR_LABELS="$XCAT_CLEAR_LABELS /dev/$xcat_provider"
        xcat_label_hash=$(printf '%s\n' "$xcat_labels" | sha256 -q) || return 1
        XCAT_REINSTALL_LABELS="$XCAT_REINSTALL_LABELS$xcat_provider $xcat_label_hash
"
    else
        [ "$xcat_owner_name" != "'zroot'" ] || { xcat_error 'An unselected disk contains a zroot pool'; return 1; }
        xcat_other_guids="$xcat_other_guids $xcat_owner_guid"
    fi
}

xcat_scan_labels()
{
    XCAT_REINSTALL_LABELS=
    XCAT_CLEAR_LABELS=
    xcat_os_guid= xcat_os_cache_guids= xcat_other_guids=
    xcat_disks=$(sysctl -n kern.disks) || return 1
    if xcat_guarded_storage; then
        xcat_selected=$(xcat_zfs_all_members) || return 1
        xcat_selected=$(printf '%s\n' "$xcat_selected" | awk '{s=s (NR==1 ? "" : " ") $1} END {print s}') || return 1
        [ -n "$xcat_selected" ] || return 1
        for xcat_disk in $xcat_selected; do
            case " $xcat_disks " in *" $xcat_disk "*) ;; *) return 1 ;; esac
        done
    else
        case " $xcat_disks " in *" $XCAT_TARGET_DISK "*) ;; *) return 1 ;; esac
    fi
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
            if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
                xcat_labels=$(timeout -k 5 60 zdb -l "/dev/$xcat_provider" 2>/dev/null) || xcat_label_status=$?
            else
                xcat_labels=$(zdb -l "/dev/$xcat_provider" 2>/dev/null) || xcat_label_status=$?
            fi
            case "$xcat_label_status" in
                0) ;;
                2) continue ;;
                *) xcat_error "Cannot inspect ZFS labels on $xcat_provider"; return 1 ;;
            esac
            if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
                xcat_scan_os_label || return 1
                continue
            fi
            printf '%s\n' "$xcat_labels" | awk '$1 == "pool_guid:" {found=1} END {exit !found}' ||
                { xcat_error "Cannot identify ZFS labels on $xcat_provider"; return 1; }
            if xcat_guarded_storage; then
                for xcat_member in $xcat_selected; do
                    [ "$xcat_member" != "$xcat_disk" ] || {
                        if xcat_extended_storage && [ "$XCAT_DISK_ACTION" = erase ]; then
                            printf '%s\n' "$xcat_labels" | awk '
                                $1 == "name:" {found++; if ($2 != "\047zroot\047") bad=1}
                                END {exit !found || bad}' || { xcat_error 'An OS disk contains a data pool'; return 1; }
                            XCAT_CLEAR_LABELS="$XCAT_CLEAR_LABELS /dev/$xcat_provider"
                            xcat_label_hash=$(printf '%s\n' "$xcat_labels" | sha256 -q) || return 1
                            XCAT_REINSTALL_LABELS="$XCAT_REINSTALL_LABELS$xcat_provider $xcat_label_hash
"
                            continue 2
                        fi
                        xcat_error 'A selected disk already contains ZFS labels'; return 1
                    }
                done
            fi
            if xcat_guarded_storage || [ "$xcat_disk" != "$XCAT_TARGET_DISK" ]; then
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
    for xcat_cache_guid in $xcat_os_cache_guids; do
        [ -n "$xcat_os_guid" ] && [ "$xcat_cache_guid" = "$xcat_os_guid" ] || {
            xcat_error 'An OS cache device does not belong to the selected root pool'; return 1
        }
    done
    for xcat_other_guid in $xcat_other_guids; do
        [ "$xcat_other_guid" != "$xcat_os_guid" ] || {
            xcat_error 'An unselected device belongs to the root pool'; return 1
        }
    done
    return 0
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
    if [ "$XCAT_FORMAT" != xcat-freebsd-install-1 ]; then
        printf 'DISTRIBUTIONS=""\nexport nonInteractive="YES"\n'
    else
        printf 'DISTRIBUTIONS="base.txz kernel.txz"\nBSDINSTALL_DISTDIR="%s/dist"\nexport nonInteractive="YES"\n' "$XCAT_WORK"
    fi
    if [ "$XCAT_FILESYSTEM" = zfs ]; then
        if xcat_guarded_storage; then
            xcat_members=$(xcat_zfs_members) || return 1
            xcat_disks=$(printf '%s\n' "$xcat_members" | awk '{s=s (NR == 1 ? "" : " ") $1} END {print s}') || return 1
            printf 'export ZFSBOOT_DISKS="%s"\nexport ZFSBOOT_VDEV_TYPE="%s"\n' "$xcat_disks" "$XCAT_ZFS_TOPOLOGY"
        else
            printf 'export ZFSBOOT_DISKS="%s"\nexport ZFSBOOT_VDEV_TYPE="stripe"\n' "$XCAT_TARGET_DISK"
        fi
        printf 'export ZFSBOOT_POOL_NAME="zroot"\nexport ZFSBOOT_PARTITION_SCHEME="GPT"\nexport ZFSBOOT_SWAP_SIZE="%s"\n' "$XCAT_SWAP_SIZE"
        if xcat_extended_storage; then
            printf 'export ZFSBOOT_FORCE_4K_SECTORS=""\nexport ZFSBOOT_POOL_CREATE_OPTIONS="-o ashift=%s -O compression=%s -O atime=off' \
                "$XCAT_ZFS_ASHIFT" "$XCAT_ZFS_COMPRESSION"
            if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
                printf ' -O special_small_blocks=%s' "$XCAT_ZFS_SPECIAL_SMALL_BLOCKS"
            fi
            printf '"\n'
        fi
        if [ "$XCAT_FORMAT" = xcat-freebsd-install-6 ]; then
            xcat_auxiliary=$(xcat_zfs_auxiliary arguments) || return 1
            xcat_auxiliary=$(printf '%s\n' "$xcat_auxiliary" | awk 'NF {s=s (length(s) ? " " : "") $0} END {print s}') || return 1
            printf 'export XCAT_ZFS_AUXILIARY="%s"\n' "$xcat_auxiliary"
        fi
        if [ -n "${XCAT_ZFS_DATASETS_BASE64:-}" ]; then
            xcat_datasets=$(xcat_zfs_dataset_plan) || return 1
            printf 'export ZFSBOOT_DATASETS="\n'
            printf '%s\n' "$xcat_datasets" | awk -F '\t' '{sub(/^zroot/,"",$1); print $1 " " $2}'
            printf '"\n'
        fi
    elif [ "$XCAT_SWAP_SIZE" = 0 ]; then
        printf 'PARTITIONS="%s GPT { auto freebsd-ufs / }"\n' "$XCAT_TARGET_DISK"
    else
        printf 'PARTITIONS="%s GPT { %s freebsd-swap, auto freebsd-ufs / }"\n' "$XCAT_TARGET_DISK" "$XCAT_SWAP_SIZE"
    fi
    cat "$1" || return 1
    if [ -n "${XCAT_BOOTSTRAP_NETWORK_BASE64:-}" ]; then
        . /usr/local/libexec/xcat-network.sh
        printf '\nsysrc -x ifconfig_%s\n' "$XCAT_PROVISIONING_IF"
        [ -z "$XCAT_GATEWAY" ] || printf 'sysrc -x defaultrouter\n'
        printf '\ncat >> /etc/rc.conf <<\047XCAT_BOOTSTRAP_RC\047\n'
        xcat_network_rc || return 1
        printf 'XCAT_BOOTSTRAP_RC\n'
        printf 'install -d -m 0700 /var/db/xcat/network\ncat > /var/db/xcat/network/current <<\047XCAT_BOOTSTRAP_PLAN\047\n'
        cat "$XCAT_WORK/target-network.plan" || return 1
        printf 'XCAT_BOOTSTRAP_PLAN\nchmod 0600 /var/db/xcat/network/current\n'
    fi
    if [ "$XCAT_FORMAT" = xcat-freebsd-install-3 ] || xcat_guarded_storage; then
        printf '\ncat >> /boot/loader.conf <<\047XCAT_LOADER_SETTINGS\047\n'
        xcat_boot_options "$XCAT_TARGET_BOOT_OPTIONS_BASE64" && xcat_console_settings || return 1
        printf 'XCAT_LOADER_SETTINGS\n'
        if [ "$XCAT_CONSOLE_PORT" != none ]; then
            xcat_getty_flow='hw@'
            [ "$XCAT_CONSOLE_FLOW" != hard ] || xcat_getty_flow=hw
            printf 'printf '\''\\nxcatserial:np:nc:sp#%s:%s:\\n'\'' >> /etc/gettytab\n' "$XCAT_CONSOLE_SPEED" "$xcat_getty_flow"
            printf 'awk '\''$1 != "ttyu%s"'\'' /etc/ttys > /etc/ttys.xcat\n' "$XCAT_CONSOLE_PORT"
            printf 'printf '\''ttyu%s "/usr/libexec/getty xcatserial" vt100 on insecure\\n'\'' >> /etc/ttys.xcat\n' "$XCAT_CONSOLE_PORT"
            printf 'chmod 0644 /etc/ttys.xcat\nmv /etc/ttys.xcat /etc/ttys\n'
        fi
    fi
    printf '\ninstall -d -m 0755 /usr/local/libexec\ncat > /usr/local/libexec/xcat-install-lib.sh <<\047XCAT_INSTALL_LIB\047\n'
    cat "${2:-${1%/*}/xcat-install-lib.sh}" || return 1
    printf '\nXCAT_INSTALL_LIB\nchmod 0444 /usr/local/libexec/xcat-install-lib.sh\n'
}

xcat_pkgbase_workspace()
{
    [ "$(sysctl -n vm.swap_total)" = 0 ] || {
        xcat_error 'Pkgbase preparation requires RAM without active swap'
        return 1
    }
    xcat_ram_bytes=$(sysctl -n hw.physmem) || return 1
    case "$xcat_ram_bytes" in ''|*[!0-9]*) return 1 ;; esac
    [ "${#xcat_ram_bytes}" -le 15 ] && [ "$xcat_ram_bytes" -gt 0 ] || return 1
    xcat_pkgbase_work=$XCAT_WORK/pkgbase-work
    mkdir -m 0700 "$xcat_pkgbase_work" || return 1
    mount -t tmpfs -o "size=$xcat_ram_bytes,mode=0700" tmpfs "$xcat_pkgbase_work" || return 1
    cp -p "$XCAT_WORK/config" "$xcat_pkgbase_work/config" &&
        chmod 0400 "$xcat_pkgbase_work/config" &&
        cmp "$XCAT_WORK/config" "$xcat_pkgbase_work/config" || return 1
    XCAT_WORK=$xcat_pkgbase_work
}

xcat_prepare_pkgbase()
{
    case "$XCAT_FORMAT" in xcat-freebsd-install-2|xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6) ;; *) return 1 ;; esac
    xcat_hex "$XCAT_ATTEMPT" 32 || return 1
    # The caller owns begin and disk access. This entry only fills its RAM workspace.
    env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C XCAT_ATTEMPT="$XCAT_ATTEMPT" \
        /bin/timeout -k 5 1810 /usr/libexec/bsdinstall/pkgbase \
        --xcat-prepare-1 "$XCAT_WORK/config" "$XCAT_WORK"
}

xcat_install_system()
{
    xcat_install_parent=$XCAT_WORK
    case "$XCAT_FORMAT" in
        xcat-freebsd-install-1) ;;
        xcat-freebsd-install-2|xcat-freebsd-install-3|xcat-freebsd-install-4|xcat-freebsd-install-5|xcat-freebsd-install-6)
            [ -f /xcat/runtime.tsv ] && [ ! -L /xcat/runtime.tsv ] || {
                xcat_error 'Pkgbase installation runtime is not available'
                return 1
            }
            xcat_pkgbase_workspace || return 1
            xcat_prepare_pkgbase > "$XCAT_WORK/prepare.log" 2>&1 || return 1
            ;;
        *) xcat_error 'Unsupported installation configuration'; return 1 ;;
    esac
    kldload -n zfs && kldload -n geom_eli || return 1
    if xcat_guarded_storage; then
        if xcat_extended_storage && [ "$XCAT_DISK_ACTION" = erase ]; then
            xcat_check_zfs_reinstall > "$XCAT_WORK/reinstall.snapshot" || return 1
        else
            xcat_snapshot=$(xcat_check_zfs_initial) || return 1
            printf '%s\n' "$xcat_snapshot" > "$XCAT_WORK/storage.snapshot" || return 1
        fi
        for xcat_directory in target etc boot tmp; do
            mkdir -m 0700 "$xcat_install_parent/$xcat_directory" || return 1
        done
    else
        xcat_check_disk && xcat_scan_labels || return 1
    fi
    if [ "$XCAT_FORMAT" = xcat-freebsd-install-1 ]; then
        xcat_fetch_distributions || return 1
    fi
    xcat_write_installer "$1" "${2:-${1%/*}/xcat-install-lib.sh}" > "$XCAT_WORK/installerconfig" || return 1
    xcat_status begin || return 1
    set --
    if xcat_guarded_storage; then
        if xcat_extended_storage && [ "$XCAT_DISK_ACTION" = erase ]; then
            xcat_erase_os_disks "$XCAT_WORK/reinstall.snapshot" > "$XCAT_WORK/storage.snapshot" || return 1
        else
            xcat_current_snapshot=$(xcat_check_zfs_initial) || return 1
            [ "$xcat_current_snapshot" = "$xcat_snapshot" ] || {
                xcat_error 'The ZFS disk set changed while awaiting the controller'
                return 1
            }
        fi
        /usr/local/libexec/xcat-storage "$xcat_install_parent/job" arm \
            "$XCAT_WORK/config" "$XCAT_WORK/storage.snapshot" || return 1
        set -- "XCAT_STORAGE_WORK=$xcat_install_parent/job" \
            "BSDINSTALL_CHROOT=$xcat_install_parent/target" "BSDINSTALL_TMPETC=$xcat_install_parent/etc" \
            "BSDINSTALL_TMPBOOT=$xcat_install_parent/boot" "TMPDIR=$xcat_install_parent/tmp"
    else
        xcat_check_disk || return 1
        for xcat_provider in $XCAT_CLEAR_LABELS; do zpool labelclear -f "$xcat_provider" || return 1; done
    fi
    timeout 3600 env -i PATH="$PATH" LC_ALL=C TERM="${TERM:-vt100}" \
        XCAT_MASTER="$XCAT_MASTER" XCAT_PORT="$XCAT_PORT" XCAT_GENERATION="$XCAT_GENERATION" \
        XCAT_ATTEMPT="$XCAT_ATTEMPT" XCAT_HOSTNAME="$XCAT_HOSTNAME" \
        XCAT_PROVISIONING_IF="$XCAT_PROVISIONING_IF" XCAT_IPV4="$XCAT_IPV4" \
        XCAT_NETMASK="$XCAT_NETMASK" XCAT_GATEWAY="$XCAT_GATEWAY" XCAT_NAMESERVERS="$XCAT_NAMESERVERS" \
        XCAT_AUTHORIZED_KEY_BASE64="$XCAT_AUTHORIZED_KEY_BASE64" XCAT_WORK="$XCAT_WORK" \
        "$@" bsdinstall script "$XCAT_WORK/installerconfig" > "$XCAT_WORK/bsdinstall.log" 2>&1 || return 1
    if xcat_guarded_storage; then
        xcat_storage_phase=$(cat "$xcat_install_parent/job/phase") || return 1
        [ "$xcat_storage_phase" = complete ] &&
            [ ! -e "$xcat_install_parent/job/failed" ] && [ ! -e "$xcat_install_parent/job/busy" ] &&
            [ ! -e "$xcat_install_parent/job/ready" ] || return 1
    fi
    xcat_status complete
}
