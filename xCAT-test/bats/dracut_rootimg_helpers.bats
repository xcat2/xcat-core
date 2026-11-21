#!/usr/bin/env bats

load 'helpers/script_sandbox'
load 'helpers/dracut_module'

VARIANTS='rh/dracut_033 rh/dracut_047 rh/dracut_105/stateless sles/dracut_033 ubuntu/dracut'

setup()
{
    setup_script_sandbox cp mkdir dirname grep cmp stat
    mkdir -p "$fixture/module" "$fixture/out" "$fixture/etc/udev/rules.d"
    mkdir -p "$fixture/sbin"
    sandbox+=(--tmpfs /usr --ro-bind "$fixture/bin" /usr/bin --ro-bind "$fixture/sbin" /usr/sbin)
    for directory in /usr/lib /usr/lib64; do
        [ ! -d "$directory" ] || sandbox+=(--ro-bind "$directory" "$directory")
    done
    [ -L /sbin ] || sandbox+=(--ro-bind "$fixture/sbin" /sbin)
    printf '# xcat\n' >"$fixture/etc/udev/rules.d/01-xcat.rules"
    cat >"$fixture/dracut.sh" <<'SH'
inst() {
    mkdir -p "/run/fixture/out$(dirname "$2")" &&
        cp -p "$1" "/run/fixture/out$2"
}
inst_simple() { inst "$@"; }
inst_script() { inst "$@"; }
inst_hook() { inst "$3" "/lib/dracut/hooks/$1/$2-${3##*/}"; }
dracut_install() {
    for file do
        case "$file" in /usr/*/uftpd) inst "$file" "$file" || return ;; esac
    done
    return 0
}
SH
}

stage_module()
{
    local variant=$1
    rm -rf "$fixture/module" "$fixture/out"
    mkdir -p "$fixture/module" "$fixture/out"
    stage_dracut_module "$variant" "$fixture/module"
    cp "$(repo_path xCAT/postscripts/updateflag.awk)" "$fixture/module/xcat-updateflag"
    hook=install.netboot
    [ "$variant" != rh/dracut_105/stateless ] || hook=module-setup.sh
}

install_module()
{
    run "${sandbox[@]}" /bin/bash -c '
        . /run/fixture/dracut.sh
        moddir=/run/fixture/module
        if [ "$1" = module-setup.sh ]; then
            . "$moddir/$1"
            install
        else
            . "$moddir/$1"
        fi
    ' install "$hook"
}

receiver()
{
    printf '#!/bin/sh\n# %s receiver\nexit 0\n' "$1" >"$fixture/$1/uftpd"
    chmod 755 "$fixture/$1/uftpd"
}

add_fetch_helper()
{
    cp "$(repo_path xCAT-server/share/xcat/netboot/imgutils/xcat-rootimg-fetch.sh)" "$fixture/module/"
}

@test 'all stateless hooks deliver the checksum helper without UFTP' {
    receiver bin
    receiver sbin
    for variant in $VARIANTS; do
        stage_module "$variant"
        install_module
        [ "$status" -eq 0 ] || { echo "$variant: $output"; return 1; }
        cmp "$fixture/module/xcat-rootimg-checksum.sh" "$fixture/out/lib/xcat-rootimg-checksum.sh"
        [ ! -e "$fixture/out/lib/xcat-rootimg-fetch.sh" ]
        [ ! -e "$fixture/out/lib/xcat-rootimg-install.sh" ]
        [ ! -e "$fixture/out/usr/sbin/uftpd" ]
        [ ! -e "$fixture/out/usr/bin/uftpd" ]
    done
}

@test 'all stateless hooks prefer the sbin receiver when both locations are executable' {
    receiver bin
    receiver sbin
    for variant in $VARIANTS; do
        stage_module "$variant"
        add_fetch_helper
        install_module
        [ "$status" -eq 0 ] || { echo "$variant: $output"; return 1; }
        cmp "$fixture/module/xcat-rootimg-fetch.sh" "$fixture/out/lib/xcat-rootimg-fetch.sh"
        cmp "$fixture/sbin/uftpd" "$fixture/out/usr/sbin/uftpd"
        [ ! -e "$fixture/out/usr/bin/uftpd" ]
    done
}

@test 'all stateless hooks install the bin receiver when the sbin receiver is absent or not executable' {
    receiver bin
    for variant in $VARIANTS; do
        for sbin in absent nonexecutable; do
            rm -f "$fixture/sbin/uftpd"
            if [ "$sbin" = nonexecutable ]; then
                receiver sbin
                chmod 644 "$fixture/sbin/uftpd"
            fi
            stage_module "$variant"
            add_fetch_helper
            install_module
            [ "$status" -eq 0 ] || { echo "$variant: $output"; return 1; }
            cmp "$fixture/bin/uftpd" "$fixture/out/usr/bin/uftpd"
            [ ! -e "$fixture/out/usr/sbin/uftpd" ]
        done
    done
}

@test 'all stateless hooks retain the fetch helper when neither receiver location is executable' {
    for variant in $VARIANTS; do
        stage_module "$variant"
        add_fetch_helper
        install_module
        [ "$status" -eq 0 ] || { echo "$variant: $output"; return 1; }
        cmp "$fixture/module/xcat-rootimg-fetch.sh" "$fixture/out/lib/xcat-rootimg-fetch.sh"
        [ ! -e "$fixture/out/usr/sbin/uftpd" ]
        [ ! -e "$fixture/out/usr/bin/uftpd" ]
    done
}

@test 'all stateless hooks stop when the installation policy helper is missing' {
    for variant in $VARIANTS; do
        stage_module "$variant"
        rm "$fixture/module/xcat-rootimg-install.sh"
        install_module
        [ "$status" -ne 0 ] || { echo "$variant accepted a missing installation helper"; return 1; }
        [[ "$output" == *xcat-rootimg-install.sh* ]]
    done
}

@test 'all stateless hooks stop when the checksum helper cannot be installed' {
    for variant in $VARIANTS; do
        stage_module "$variant"
        rm "$fixture/module/xcat-rootimg-checksum.sh"
        install_module
        [ "$status" -ne 0 ] || { echo "$variant accepted a missing checksum helper"; return 1; }
        [[ "$output" == *xcat-rootimg-checksum.sh* ]]
        [ ! -e "$fixture/out/lib/xcat-rootimg-checksum.sh" ]
    done
}

@test 'all stateless hooks reject a missing checksum helper even if inst reports success' {
    printf '\ninst() { :; }\n' >>"$fixture/dracut.sh"
    for variant in $VARIANTS; do
        stage_module "$variant"
        rm "$fixture/module/xcat-rootimg-checksum.sh"
        install_module
        [ "$status" -ne 0 ] || { echo "$variant accepted a missing checksum helper"; return 1; }
        [[ "$output" == *"Cannot read /run/fixture/module/xcat-rootimg-checksum.sh"* ]]
    done
}
