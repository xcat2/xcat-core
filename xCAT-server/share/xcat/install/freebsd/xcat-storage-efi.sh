# UEFI operations for the initial-install storage guard.

storage_efi_load()
{
    storage_primary=/dev/gpt/${storage_prefix}0
    storage_efi_label=xcat-$XCAT_GENERATION
    storage_extra= storage_efi_mount= storage_efi_stage=unstarted storage_efi_index=0
    if [ -f "$storage_work/efi-stage" ]; then
        storage_efi_stage=$(cat "$storage_work/efi-stage")
        storage_efi_index=$(cat "$storage_work/efi-index")
        storage_extra=$(cat "$storage_work/efi-extra")
        storage_efi_mount=$(cat "$storage_work/efi-mount")
    fi
    case "$storage_efi_index" in ''|*[!0-9]*) exit 1 ;; esac
    [ "$storage_efi_index" -le "$storage_count" ]
}

storage_efi_modes()
{
    case "$storage_phase" in
        mounted|boot-configured)
            printf '%s\n' "$storage_members" | awk -F '\t' 'NR == 1 {print $1 "p1"}'
            ;;
    esac
    if [ -n "$storage_extra" ]; then
        awk -F '\t' -v esp="$storage_extra" '
            $1 == "P" && $5 == "efi" && "/dev/gpt/" $6 == esp {print $4; found++}
            END {if (found != 1) exit 1}' "$storage_work/table"
    fi
}

storage_efi_fstab()
{
    awk -v primary="$storage_primary" -v options="$2" '
        BEGIN {pass=(options == "rw,noauto" ? 0 : 2)}
        NF && $1 !~ /^#/ {
            found++
            if (NF != 6 || $1 != primary || $2 != "/boot/efi" ||
                $3 != "msdosfs" || $4 != options || $5 != pass || $6 != pass) bad=1
        }
        END {exit bad || found != 1}' "$1"
}

storage_efi_mounts()
{
    XCAT_STORAGE_TABLE="$storage_table_now" XCAT_STORAGE_MEMBERS="$storage_snapshot" \
        awk -v root="$storage_root" -v phase="$storage_phase" -v primary="$storage_primary" \
        -v extra="$storage_extra" -v temp="$storage_efi_mount" '
        BEGIN {
            n=split(ENVIRON["XCAT_STORAGE_MEMBERS"], rows, "\n")
            for (i=1;i<=n;i++) {split(rows[i], f, "\t"); serial[f[1]]=f[2]}
            n=split(ENVIRON["XCAT_STORAGE_TABLE"], rows, "\n")
            for (i=1;i<=n;i++) {
                split(rows[i], f, "\t"); if (f[1] != "P" || f[5] != "efi") continue
                selected["/dev/" f[4]]=1; selected["/dev/gpt/" f[6]]=1
                selected["/dev/gptid/" f[7]]=1
                selected["/dev/diskid/DISK-" serial[f[2]] "p1"]=1
            }
            if (phase == "mounted" || phase == "boot-configured") expected[primary]=root "/boot/efi"
            if (extra != "") expected[extra]=temp
        }
        $1 in selected {
            if (!($1 in expected) || $2 != expected[$1] || $3 != "msdosfs" || seen[$1]++) bad=1
        }
        END {for (p in expected) if (seen[p] != 1) bad=1; exit bad}' <<XCAT_EFI_MOUNTS
$storage_mounts_now
XCAT_EFI_MOUNTS
}

storage_efi_canonical()
{
    storage_efi_real=$(realpath "$1")
    [ "$storage_efi_real" = "$1" ]
}

storage_efi_emptydir()
{
    storage_efi_contents=$(find "$1" -mindepth 1 -maxdepth 1 -print)
    [ -z "$storage_efi_contents" ]
}

storage_efi_hash_matches()
{
    storage_efi_hash=$(sha256 -q "$1")
    xcat_hex "$storage_efi_hash" 64
    storage_efi_expected_hash=$(cat "$2")
    xcat_hex "$storage_efi_expected_hash" 64
    [ "$storage_efi_hash" = "$storage_efi_expected_hash" ]
}

storage_efi_loader()
{
    storage_loader=$storage_root/boot/loader.efi
    [ -f "$storage_loader" ] && [ ! -L "$storage_loader" ] || exit 1
    storage_efi_canonical "$storage_loader"
    storage_efi_hash_matches "$storage_loader" "$storage_work/efi-loader"
    storage_efi_hash_matches "$storage_tmpdir/bsdinstall-esps" "$storage_work/efi-esps"
}

storage_efi_copy()
{
    [ -f "$1" ] && [ ! -L "$1" ] || exit 1
    storage_efi_canonical "$1"
    storage_efi_hash_matches "$1" "$storage_work/efi-loader"
}

storage_efi_snapshot()
{
    storage_nv=$1
    mkdir -m 0700 "$storage_nv"
    efivar -l -R > "$storage_nv/variables"
    awk -v prefix=8be4df61-93ca-11d2-aa0d-00e098032b8c- '
        index($0, prefix) == 1 {
            name=substr($0, length(prefix)+1)
            if (name ~ /^Boot[0-9A-Fa-f]{4}$/ || name ~ /^(BootOrder|BootCurrent|BootNext|Timeout)$/) print name
        }' "$storage_nv/variables" > "$storage_nv/names.raw"
    sort "$storage_nv/names.raw" > "$storage_nv/names"
    sort -u "$storage_nv/names" > "$storage_nv/names.unique"
    cmp "$storage_nv/names" "$storage_nv/names.unique"
    : > "$storage_nv/hashes"
    while IFS= read -r storage_var; do
        efivar -b -N -p -n "8be4df61-93ca-11d2-aa0d-00e098032b8c-$storage_var" > "$storage_nv/$storage_var"
        storage_efi_hash=$(sha256 -q "$storage_nv/$storage_var")
        xcat_hex "$storage_efi_hash" 64
        printf '%s\t%s\n' "$storage_var" "$storage_efi_hash" >> "$storage_nv/hashes"
    done < "$storage_nv/names"
    efibootmgr -v > "$storage_nv/entries"
}

storage_efi_entry()
{
    storage_new=$(awk -F '\t' '
        NR == FNR {old[$1]=$2; next}
        $1 == "BootOrder" {delete old[$1]; next}
        $1 in old {if (old[$1] != $2) bad=1; delete old[$1]; next}
        {if ($1 !~ /^Boot[0-9A-F]{4}$/) bad=1; added++; name=$1}
        END {for (key in old) bad=1; if (bad || added != 1) exit 1; print name}' \
        "$storage_work/efi-before/hashes" "$storage_work/efi-after/hashes")
    [ -f "$storage_work/efi-after/BootOrder" ]
    od -An -N2 -tu2 "$storage_work/efi-after/BootOrder" > "$storage_work/efi-order-head"
    storage_order=$(awk '
        NF != 1 || $1 !~ /^[0-9]+$/ || $1 > 65535 {bad=1}
        {value=$1}
        END {if (bad || NR != 1) exit 1; print value}' "$storage_work/efi-order-head")
    storage_number=$(printf '%04X' "$storage_order")
    [ "Boot$storage_number" = "$storage_new" ]
    dd if="$storage_work/efi-after/BootOrder" of="$storage_work/efi-order-tail" bs=1 skip=2 2> "$storage_work/efi-order.log"
    if [ -f "$storage_work/efi-before/BootOrder" ]; then
        cmp "$storage_work/efi-before/BootOrder" "$storage_work/efi-order-tail"
    else
        [ ! -s "$storage_work/efi-order-tail" ]
    fi
    od -An -N4 -tu1 "$storage_work/efi-after/$storage_new" > "$storage_work/efi-attributes"
    awk 'NF != 4 || $1 != 1 || $2 != 0 || $3 != 0 || $4 != 0 {bad=1} END {exit bad || NR != 1}' "$storage_work/efi-attributes"
    storage_efi_path=$(efibootmgr -u "$storage_root/boot/efi/efi/freebsd/loader.efi")
    storage_efi_path=${storage_efi_path#"$storage_root/boot/efi/efi/freebsd/loader.efi -> "}
    storage_efi_disk=$(awk -F '\t' -v p="$storage_primary" '
        $1 == "P" && $5 == "efi" && "/dev/gpt/" $6 == p {
            printf "HD(1,GPT,%s,0x%x,0x%x)/File(\\efi\\freebsd\\loader.efi)", $7, $10/$9, $8/$9
            found++
        } END {if (found != 1) exit 1}' "$storage_work/table")
    [ "$storage_efi_path" = "$storage_efi_disk" ]
    XCAT_STORAGE_EFI_ENTRY="$storage_new* $storage_efi_label $storage_efi_path" awk '
        BEGIN {expected=ENVIRON["XCAT_STORAGE_EFI_ENTRY"]}
        {sub(/^ /, ""); if ($0 == expected) found++}
        END {exit found != 1}' "$storage_work/efi-after/entries"
    printf '%s\n' "$storage_new" > "$storage_work/efi-entry"
}

storage_efi_primary()
{
    [ "$#" -eq 2 ] && [ "$storage_phase" = mounted ] && [ "$storage_efi_stage" = unstarted ] || exit 1
    storage_paths
    [ "$1" = "$PATH_FSTAB" ] && [ "$2" = "$storage_root/boot/efi" ] || exit 1
    storage_check
    storage_mounts 1 1
    storage_fstab "$1"
    storage_efi_arch=$(sysctl -n machdep.efi_arch)
    [ "$storage_efi_arch" = amd64 ]
    [ -f "$storage_root/boot/loader.efi" ] && [ ! -L "$storage_root/boot/loader.efi" ] || exit 1
    sha256 -q "$storage_root/boot/loader.efi" > "$storage_work/efi-loader"
    # Native zfsboot omits the extra-ESP list for a single-disk install.
    if [ "$storage_count" -eq 1 ] && [ ! -e "$storage_tmpdir/bsdinstall-esps" ] &&
        [ ! -L "$storage_tmpdir/bsdinstall-esps" ]; then
        : > "$storage_tmpdir/bsdinstall-esps"
    fi
    [ -f "$storage_tmpdir/bsdinstall-esps" ] && [ ! -L "$storage_tmpdir/bsdinstall-esps" ] || exit 1
    storage_esps=$(awk -v prefix="$storage_prefix" -v count="$storage_count" 'BEGIN {
        for (i=1;i<count;i++) print "/dev/gpt/" prefix i}')
    storage_esps_read=$(cat "$storage_tmpdir/bsdinstall-esps")
    [ "$storage_esps_read" = "$storage_esps" ]
    sha256 -q "$storage_tmpdir/bsdinstall-esps" > "$storage_work/efi-esps"
    storage_efi_loader
    storage_efi_emptydir "$2"
    storage_efi_snapshot "$storage_work/efi-before"
    awk -v label="$storage_efi_label" '$2 == label {exit 1}' "$storage_work/efi-before/entries"
    printf 'directories\n' > "$storage_work/efi-stage"
    printf '0\n' > "$storage_work/efi-index"
    : > "$storage_work/efi-extra"
    : > "$storage_work/efi-mount"
    storage_release
    printf '%s\n' "$storage_primary"
}

storage_efi_before()
{
    [ "$#" -ge 2 ] && [ "$storage_phase" = mounted ] || exit 1
    storage_paths
    storage_check
    storage_mounts 1 1
    storage_efi_loader
    storage_esp=$1
    shift
    storage_mnt=$storage_root/boot/efi
    if [ "$storage_efi_stage" = firmware ]; then
        [ "$storage_esp" = "$storage_primary" ]
    else
        [ "$storage_esp" = "/dev/gpt/$storage_prefix$storage_efi_index" ]
        [ "$storage_efi_index" -eq 0 ] || storage_mnt=$storage_efi_mount
    fi
    case "$storage_efi_stage:$1" in
        directories:mkdir)
            [ "$#" -eq 4 ] && [ "$2" = -p ] && [ "$3" = "$storage_mnt/efi/freebsd" ] && [ "$4" = "$storage_mnt/efi/boot" ] || exit 1
            [ ! -e "$storage_mnt/efi" ] && [ ! -L "$storage_mnt/efi" ] || exit 1
            storage_kind=efi-directories
            ;;
        freebsd:cp|fallback:cp)
            [ "$#" -eq 3 ] && [ "$2" = "$storage_loader" ] || exit 1
            if [ "$storage_efi_stage" = freebsd ]; then
                [ "$3" = "$storage_mnt/efi/freebsd" ]
                storage_destination=$3/loader.efi
            else
                [ "$3" = "$storage_mnt/efi/boot/bootx64.efi" ]
                storage_destination=$3
            fi
            storage_efi_canonical "$(dirname "$storage_destination")"
            [ ! -e "$storage_destination" ] && [ ! -L "$storage_destination" ] || exit 1
            storage_kind=efi-$storage_efi_stage
            ;;
        mount:mount)
            [ "$#" -eq 5 ] && [ "$2:$3:$4" = "-t:msdos:$storage_esp" ] && [ -z "$storage_extra" ] || exit 1
            [ "$(dirname "$5")" = "$storage_tmpdir" ]
            storage_efi_canonical "$5"
            case "$(basename "$5")" in bsdinstall-esp.*) ;; *) exit 1 ;; esac
            storage_efi_owner=$(stat -f '%u:%Lp' "$5")
            [ "$storage_efi_owner" = 0:700 ]
            storage_efi_emptydir "$5"
            [ -z "$storage_efi_mount" ] || [ "$storage_efi_mount" = "$5" ]
            printf '%s\n' "$5" > "$storage_work/efi-mount"
            storage_kind=efi-mount
            ;;
        umount:umount)
            [ "$#" -eq 2 ] && [ "$2" = "$storage_efi_mount" ] && [ "$storage_extra" = "$storage_esp" ] || exit 1
            storage_kind=efi-umount
            ;;
        firmware:update_uefi_bootentry)
            [ "$#" -eq 2 ] && [ "$2" = "$storage_mnt/efi/freebsd/loader.efi" ] &&
                [ "${EFI_LABEL_NAME:-}" = "$storage_efi_label" ] && [ -z "$storage_extra" ] || exit 1
            storage_efi_copy "$2"
            storage_efi_snapshot "$storage_work/efi-pre-update"
            cmp "$storage_work/efi-before/hashes" "$storage_work/efi-pre-update/hashes"
            storage_kind=efi-firmware
            ;;
        *) exit 1 ;;
    esac
    printf '%s\n' "$storage_kind" > "$storage_work/kind"
    storage_approve boot-after
}

storage_efi_after()
{
    [ "$#" -ge 2 ] && [ "$storage_phase" = mounted ] || exit 1
    storage_paths
    storage_esp=$1
    storage_kind=$(cat "$storage_work/kind")
    case "$storage_kind" in
        efi-mount) storage_extra=$storage_esp ;;
        efi-umount) storage_extra= ;;
    esac
    storage_check
    storage_mounts 1 1
    storage_efi_loader
    storage_mnt=$storage_root/boot/efi
    [ "$storage_efi_index" -eq 0 ] || storage_mnt=$storage_efi_mount
    case "$storage_kind" in
        efi-directories)
            for storage_dir in "$storage_mnt/efi/freebsd" "$storage_mnt/efi/boot"; do
                [ -d "$storage_dir" ]
                storage_efi_canonical "$storage_dir"
            done
            storage_efi_stage=freebsd
            ;;
        efi-freebsd)
            storage_efi_copy "$storage_mnt/efi/freebsd/loader.efi"
            storage_efi_stage=fallback
            ;;
        efi-fallback)
            storage_efi_copy "$storage_mnt/efi/boot/bootx64.efi"
            storage_efi_copy "$storage_mnt/efi/freebsd/loader.efi"
            if [ "$storage_efi_index" -eq 0 ]; then
                storage_efi_index=1 storage_efi_stage=mount
            else
                storage_efi_stage=umount
            fi
            ;;
        efi-mount)
            storage_efi_emptydir "$storage_efi_mount"
            storage_efi_stage=directories
            ;;
        efi-umount)
            storage_efi_canonical "$storage_efi_mount"
            storage_efi_index=$((storage_efi_index+1)) storage_efi_stage=mount
            ;;
        efi-firmware)
            storage_efi_snapshot "$storage_work/efi-after"
            storage_efi_entry
            storage_efi_stage=complete
            ;;
        *) exit 1 ;;
    esac
    if [ "$storage_efi_stage" = mount ] && [ "$storage_efi_index" -eq "$storage_count" ]; then storage_efi_stage=firmware; fi
    printf '%s\n' "$storage_efi_stage" > "$storage_work/efi-stage"
    printf '%s\n' "$storage_efi_index" > "$storage_work/efi-index"
    printf '%s\n' "$storage_extra" > "$storage_work/efi-extra"
    storage_release
}

storage_efi_finish()
{
    [ "$storage_efi_stage" = complete ] && [ "$storage_efi_index" -eq "$storage_count" ] && [ -z "$storage_extra" ] || exit 1
    storage_efi_loader
    storage_efi_copy "$storage_root/boot/efi/efi/freebsd/loader.efi"
    storage_efi_copy "$storage_root/boot/efi/efi/boot/bootx64.efi"
    storage_efi_snapshot "$storage_work/efi-finish"
    cmp "$storage_work/efi-after/hashes" "$storage_work/efi-finish/hashes"
}

storage_efi_noauto()
{
    awk 'BEGIN {OFS="\t"} NF && $1 !~ /^#/ {$4="rw,noauto"; $5=0; $6=0} {print}' \
        "$storage_root/etc/fstab" > "$storage_work/efi-installed-fstab"
    cat "$storage_work/efi-installed-fstab" > "$storage_root/etc/fstab"
    storage_fstab "$storage_root/etc/fstab" rw,noauto
}
