#!/usr/bin/env bats
#
# Run the nodeset_shell_incorrectmasterip check against a scratch tftp root, with the xCAT
# commands and the net tools shadowed.

load 'helpers/shell_source'

setup()
{
    SCRIPT="$(repo_path 'xCAT-test/autotest/testcase/genesis/test.sh')"
    [ -r "$SCRIPT" ] || skip "$SCRIPT is required"
    HOST_ARCH="$(uname -m)"
    # grub2.pm names the boot loader grub2.<arch>, with every ppc64 flavour written as "ppc".
    case "$HOST_ARCH" in
    ppc64*) LOADER_NAME=ppc ;;
    *)      LOADER_NAME="$HOST_ARCH" ;;
    esac
    export SCRIPT HOST_ARCH LOADER_NAME
}

# Run `test.sh --check <loader>` against a scratch tftp root. test.sh resets PATH, so the xCAT
# commands are shadowed with shell functions, which bash resolves first. The fake nodeset writes
# the boot file the check greps, so the assertion is on the check, not on xCAT.
#
# Sets STATUS, OUTPUT, CHDEF, LOADER_AT_NODESET and LOADER_LEFT.
run_check()
{
    local loader="$1" write_boot_file="$2" nodeset_status="${3:-0}"
    local root="${BATS_TEST_TMPDIR}/$loader-$write_boot_file-$nodeset_status"
    local tftp="$root/tftpboot"
    local boot_loader="$tftp/boot/grub2/grub2.$LOADER_NAME"
    local folder write

    rm -rf "$root"
    mkdir -p "$tftp/xcat/xnba/nodes" "$tftp/boot/grub2" "$tftp/petitboot"

    case "$loader" in
    xnba)      folder="$tftp/xcat/xnba/nodes" ;;
    petitboot) folder="$tftp/petitboot" ;;
    *)         folder="$tftp/boot/grub2" ;;
    esac
    if [ "$write_boot_file" = 1 ]; then
        write="printf 'xcatd=192.168.1.1:3001 destiny=shell\n' > '$folder/testnode'"
    else
        write=":"
    fi

    cat >"$root/driver.sh" <<DRIVER
chdef() { echo "\$@" >> '$root/chdef.log'; }
lsdef() {
    if [ "\$1" = "-t" ] && [ "\$2" = "site" ]; then echo "clustersite: master=192.168.9.9"; return 0; fi
    echo "Object name: testnode"
}
ifconfig() { printf 'eth0: flags\n        inet 192.168.9.9\n\n'; }
netstat() { printf 'Kernel\nIface\neth0\neth1\nlo\n'; }
ip() { return 0; }
makenetworks() { return 0; }
tabdump() { return 0; }
makehosts() { return 0; }
rmdef() { return 0; }
nodeset() {
    if [ -e '$boot_loader' ]; then echo yes > '$root/loader.at.nodeset'; else echo no > '$root/loader.at.nodeset'; fi
    $write
    return $nodeset_status
}
export TFTPDIR='$tftp'
. '$SCRIPT' --check $loader
DRIVER

    OUTPUT="$(/bin/bash "$root/driver.sh" 2>&1)" && STATUS=0 || STATUS=$?
    CHDEF="$(read_file_or_empty "$root/chdef.log")"
    LOADER_AT_NODESET="$(read_file_or_empty "$root/loader.at.nodeset")"
    LOADER_LEFT=0
    [ -e "$boot_loader" ] && LOADER_LEFT=1
    return 0
}

@test "the xnba check passes and defines the node with the management node architecture" {
    # The case defined its node as ppc64le whatever the management node was, so nodeset could
    # not find a genesis kernel for it on x86_64 and the case could never pass there.
    run_check xnba 1
    [ "$STATUS" -eq 0 ] || { echo "$OUTPUT"; false; }
    [[ "$CHDEF" =~ (^|[[:space:]])arch=$HOST_ARCH([[:space:]]|$) ]]
    [ "$HOST_ARCH" = ppc64le ] ||
        [ "$(grep -cE '(^|[[:space:]])arch=ppc64le([[:space:]]|$)' <<<"$CHDEF")" -eq 0 ]
}

@test "the check fails when nodeset writes no boot file" {
    run_check xnba 0
    [ "$STATUS" -ne 0 ]
}

@test "the grub2 check reads the grub2 directory, and stages then removes the boot loader" {
    # grub2 and petitboot read their configuration from other directories under the tftp root.
    # xCAT builds no x86_64 or aarch64 grub2 network boot loader, so grub2.pm stops before it
    # configures anything. The check stages one for the node arch and removes it after.
    run_check grub2 1
    [ "$STATUS" -eq 0 ] || { echo "$OUTPUT"; false; }
    [ "$LOADER_AT_NODESET" = yes ]
    [ "$LOADER_LEFT" -eq 0 ]
}

@test "a nodeset that fails makes the check fail, whatever the boot file holds" {
    # grub2.pm writes the boot configuration and only then stops on a missing boot loader. The
    # check read the file that failed nodeset had already written, so it passed on the debris.
    run_check grub2 1 1
    [ "$STATUS" -ne 0 ]

    run_check xnba 1 1
    [ "$STATUS" -ne 0 ]
}
