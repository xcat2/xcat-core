#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    GENESIS_SPEC="$(require_repo_file 'xCAT-genesis-builder/xCAT-genesis-base.spec')"
    DRACUT_MODULE="$(require_repo_file 'xCAT-genesis-builder/dracut_105/el/module-setup.sh')"
    DOXCAT="$(require_repo_file 'xCAT-genesis-scripts/usr/bin/doxcat')"
    export GENESIS_SPEC DRACUT_MODULE DOXCAT
}

run_installkernel()
{
    local modules_root="$1"
    local instmods_log="$2"

    kernel=5.14.0-test
    DRACUT_MODULES_ROOT="$modules_root"
    instmods()
    {
        printf '%s\n' "$1" >>"$instmods_log"
    }

    source "$DRACUT_MODULE"
    PATH="$(sandbox_path ls head)"
    installkernel
}

run_doxcat_modprobe_preamble()
{
    local preamble="$1"
    local modprobe_log="$2"

    modprobe()
    {
        printf '%s\n' "$*" >>"$modprobe_log"
    }

    PATH="$(sandbox_path)"
    eval "$preamble"
}

run_doxcat_bootif_block()
{
    local block="$1"

    BOOTIF=01-aa-bb-cc-dd-ee-ff
    bootnic=
    log_label=test

    logger() { :; }
    # The block retries for 6000 iterations and then sleeps forever. A lookup that never finds
    # the NIC must fail the test instead of hanging it.
    sleep()
    {
        SLEEPS=$((${SLEEPS:-0} + 1))
        [ "$SLEEPS" -le 20 ] || { printf 'the BOOTIF lookup did not finish\n' >&2; exit 98; }
    }
    PATH="$(sandbox_path sed grep awk cat)"
    ip()
    {
        printf '%s\n' "$*" >>"$IP_LOG"
        if [ "$*" = "link show" ]; then
            cat <<'EOF'
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 00:11:22:33:44:55 brd ff:ff:ff:ff:ff:ff
3: ib0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 65520 qdisc mq state UP mode DEFAULT group default qlen 256
    link/infiniband 00:bb:cc:dd:ee:ff brd 00:ff:ff:ff:ff:ff
EOF
        fi
    }

    eval "$block"
    printf '%s\n' "$bootnic"
}

@test "genesis build requires kernel module packages" {
    grep -Fxq 'BuildRequires: kernel-core' "$GENESIS_SPEC"
    grep -Fxq 'BuildRequires: kernel-modules' "$GENESIS_SPEC"
    grep -Fxq 'BuildRequires: kernel-modules-extra' "$GENESIS_SPEC"
}

@test "dracut genesis module installs every module from modules.dep" {
    local modules_root="${BATS_TEST_TMPDIR}/modules"
    local modules_dep="${modules_root}/5.14.0-test/modules.dep"
    local instmods_log="${BATS_TEST_TMPDIR}/instmods.log"

    mkdir -p "${modules_root}/5.14.0-test"
    cat >"$modules_dep" <<'EOF'
kernel/drivers/infiniband/ulp/ipoib/ib_ipoib.ko.xz:
kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko.xz:
EOF

    run run_installkernel "$modules_root" "$instmods_log"
    [ "$status" -eq 0 ]
    grep -Fxq 'ib_ipoib' "$instmods_log"
    grep -Fxq 'e1000e' "$instmods_log"
}

@test "doxcat loads IP over InfiniBand support during startup" {
    local preamble
    local modprobe_log="${BATS_TEST_TMPDIR}/modprobe.log"

    preamble="$(extract_line_range "$DOXCAT" '^modprobe acpi_cpufreq' '^modprobe ib_ipoib$')" || return 1
    [ "$(printf '%s\n' "$preamble" | wc -l)" -eq 3 ]

    run run_doxcat_modprobe_preamble "$preamble" "$modprobe_log"
    [ "$status" -eq 0 ]
    grep -Fxq 'ib_ipoib' "$modprobe_log"
}

@test "doxcat falls back to InfiniBand BOOTIF lookup after Ethernet lookup misses" {
    local block

    IP_LOG="${BATS_TEST_TMPDIR}/ip.log"
    export IP_LOG
    block="$(extract_shell_if_block "$DOXCAT" 'if [ ! -z "$BOOTIF" ]; then')" || return 1
    [ "$(printf '%s\n' "$block" | wc -l)" -eq 18 ]

    run run_doxcat_bootif_block "$block"
    [ "$status" -eq 0 ]
    [ "$output" = "ib0" ]
    [ "$(grep -c '^link show$' "$IP_LOG")" -eq 2 ]
}
