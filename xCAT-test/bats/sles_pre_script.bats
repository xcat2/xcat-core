#!/usr/bin/env bats

load 'helpers/shell_source'

setup()
{
    SCRIPT_LIB="$(repo_path 'xCAT-server/share/xcat/install/scripts/scriptlib')"
    [ -r "$SCRIPT_LIB" ] || skip "$SCRIPT_LIB is required"
    export SCRIPT_LIB
}

@test "SLES 11 UEFI install changes the AutoYaST bootloader to elilo" {
    local cmdline="${BATS_TEST_TMPDIR}/cmdline"
    local profile="${BATS_TEST_TMPDIR}/modified.xml"

    printf '%s\n' 'BOOT_IMAGE=/linux install=http://192.0.2.10/install/sles11/ppc64le' >"$cmdline"
    cat >"$profile" <<'EOF'
<bootloader>
<lba_support config:type="boolean">true</lba_support>
<linear config:type="boolean">true</linear>
<location>mbr</location>
</bootloader>
EOF

    source "$SCRIPT_LIB"
    run set_sles11_uefi_bootloader "$cmdline" "$profile"
    [ "$status" -eq 0 ]
    grep -Fxq '<loader_type>elilo</loader_type>' "$profile"
    ! grep -q '<location>mbr</location>' "$profile"
    ! grep -q '<lba_support ' "$profile"
    ! grep -q '<linear ' "$profile"
}

@test "non-SLES 11 install media keeps the legacy bootloader template value" {
    local cmdline="${BATS_TEST_TMPDIR}/cmdline"
    local profile="${BATS_TEST_TMPDIR}/modified.xml"

    printf '%s\n' 'BOOT_IMAGE=/linux install=http://192.0.2.10/install/sles15/ppc64le' >"$cmdline"
    printf '%s\n' '<location>mbr</location>' >"$profile"

    source "$SCRIPT_LIB"
    run set_sles11_uefi_bootloader "$cmdline" "$profile"
    [ "$status" -eq 0 ]
    grep -Fxq '<location>mbr</location>' "$profile"
}
