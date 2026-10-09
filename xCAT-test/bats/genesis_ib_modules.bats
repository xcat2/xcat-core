#!/usr/bin/env bats

load 'helpers/doxcat_sandbox'

setup()
{
    GENESIS_SPEC=$(repo_path xCAT-genesis-base/xCAT-genesis-base.spec)
    DRACUT_MODULE=$(repo_path xCAT-genesis-base/dracut_105/el/module-setup.sh)
    [ -r "$GENESIS_SPEC" ]
    [ -r "$DRACUT_MODULE" ]
}

run_installkernel()
{
    kernel=5.14.0-test
    DRACUT_MODULES_ROOT=$1
    local instmods_log=$2
    instmods() { printf '%s\n' "$1" >>"$instmods_log"; }
    source "$DRACUT_MODULE"
    installkernel
}

@test "genesis build requires kernel module packages" {
    command -v rpmspec >/dev/null
    run rpmspec -q --buildrequires --target x86_64 \
        --undefine openEuler --undefine rhel --undefine suse_version "$GENESIS_SPEC"
    [ "$status" -eq 0 ]
    local package
    for package in kernel-core kernel-modules kernel-modules-extra; do
        printf '%s\n' "$output" | grep -Fx "$package"
    done
}

@test "dracut genesis module installs every module from modules.dep" {
    local modules_root="$BATS_TEST_TMPDIR/modules"
    local instmods_log="$BATS_TEST_TMPDIR/instmods.log"
    mkdir -p "$modules_root/5.14.0-test"
    printf '%s\n' \
        'kernel/drivers/infiniband/ulp/ipoib/ib_ipoib.ko.xz:' \
        'kernel/drivers/net/ethernet/intel/e1000e/e1000e.ko.xz:' \
        >"$modules_root/5.14.0-test/modules.dep"

    run run_installkernel "$modules_root" "$instmods_log"
    [ "$status" -eq 0 ]
    grep -Fxq ib_ipoib "$instmods_log"
    grep -Fxq e1000e "$instmods_log"
}

@test "doxcat loads IPoIB and selects an InfiniBand boot interface" {
    setup_doxcat
    add_doxcat_link eth0 BROADCAST,MULTICAST,UP ether 02:bb:cc:dd:ee:ff
    add_doxcat_link ib0 BROADCAST,MULTICAST,UP infiniband "$ib_address"
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ "$(cat "$fixture/bootnic")" = ib0 ]
    grep -Fxq ib_ipoib "$fixture/modules"
    assert_doxcat_dhcp
}

@test "doxcat prefers an exact Ethernet BOOTIF over an InfiniBand suffix" {
    setup_doxcat
    add_doxcat_link eth0 BROADCAST,MULTICAST,UP ether aa:bb:cc:dd:ee:ff
    add_doxcat_link ib0 BROADCAST,MULTICAST,UP infiniband "$ib_address"
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ "$(cat "$fixture/bootnic")" = eth0 ]
    assert_doxcat_dhcp
}
