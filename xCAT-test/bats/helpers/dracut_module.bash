#!/usr/bin/env bash

load "${BASH_SOURCE[0]%/*}/shell_source.bash"

stage_dracut_module()
{
    local variant=$1 destination=$2 helper source
    mkdir -p "$destination"
    cp -a "$(repo_path "xCAT-server/share/xcat/netboot/$variant")/." "$destination/"
    for helper in xcat-rootimg-checksum.sh xcat-rootimg-install.sh; do
        source=$(repo_path "xCAT-server/share/xcat/netboot/imgutils/$helper")
        [ ! -f "$source" ] || cp "$source" "$destination/"
    done
}
