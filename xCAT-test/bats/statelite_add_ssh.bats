#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    ADD_SSH="$(require_repo_file 'xCAT-server/share/xcat/netboot/add-on/statelite/add_ssh')"
    export ADD_SSH
}

run_sshd_config_block()
{
    local root="$1"
    local block

    # add_ssh holds this block twice; the test runs the first one.
    block="$(extract_shell_if_block "$ADD_SSH" 'if [ -r $ROOTDIR/etc/ssh/sshd_config ]' 1 2)" || return 1
    [ "$(printf '%s\n' "$block" | wc -l)" -eq 11 ] || return 1
    # Every path in the block is under $ROOTDIR, which is the scratch root.
    [[ "${block//\$ROOTDIR\/etc\//}" != */etc/* ]] || return 1
    set -u
    ROOTDIR="$root"
    require_scratch_path "$ROOTDIR" || return 1
    PATH="$(sandbox_path cp sed)"
    eval "$block"
}

@test "statelite add_ssh writes sshd settings below systemd's open-file limit" {
    local root="${BATS_TEST_TMPDIR}/rootimg"
    local sshd_config="${root}/etc/ssh/sshd_config"

    mkdir -p "${root}/etc/ssh"
    cat >"$sshd_config" <<'EOF'
X11Forwarding no
KeyRegenerationInterval 3600
MaxStartups 1024
EOF

    run run_sshd_config_block "$root"
    [ "$status" -eq 0 ]
    grep -Fxq 'X11Forwarding yes' "$sshd_config"
    grep -Fxq 'KeyRegenerationInterval 0' "$sshd_config"
    grep -Fxq '#MaxStartups 1024' "$sshd_config"
    grep -Fxq 'MaxStartups 100:30:200' "$sshd_config"
    ! grep -Fxq 'MaxStartups 1024' "$sshd_config"
}
