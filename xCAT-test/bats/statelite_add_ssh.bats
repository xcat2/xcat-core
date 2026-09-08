#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    ADD_SSH="$(repo_path 'xCAT-server/share/xcat/netboot/add-on/statelite/add_ssh')"
    [ -r "$ADD_SSH" ] || skip "$ADD_SSH is required"
    export ADD_SSH
}

run_sshd_config_block()
{
    local root="$1"
    local block

    block="$(extract_shell_if_block "$ADD_SSH" 'if [ -r $ROOTDIR/etc/ssh/sshd_config ]')" || return 1
    ROOTDIR="$root"
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
