#!/usr/bin/env bats
#
# The OpenEmbedded Genesis image runs the legacy BMC scripts through the genesis-bmcsetup
# wrapper. The wrapper puts the BMC support commands first in PATH and starts the packaged
# implementation with the arguments it was given.

load 'helpers/shell_source'

BMC_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-xcat/xcat-genesis-bmcsetup/files'

@test "the legacy BMC scripts are valid Bash" {
    for script in bmcsetup getipmi remoteimmsetup; do
        /bin/bash -n "$(require_repo_file "xCAT-genesis-scripts/usr/bin/$script")"
    done
}

@test "the BMC action helpers are valid Bash" {
    /bin/bash -n "$(require_repo_file "$BMC_FILES/genesis-bmcsetup")"
    /bin/bash -n "$(require_repo_file "$BMC_FILES/genesis-credential-wait")"
}

@test "the BMC action starts the packaged implementation, support commands first, arguments kept" {
    wrapper="$(require_repo_file "$BMC_FILES/genesis-bmcsetup")"
    support_dir="$BATS_TEST_TMPDIR/support"
    log="$BATS_TEST_TMPDIR/wrapper.log"
    mkdir -p "$support_dir"
    cat >"$BATS_TEST_TMPDIR/implementation" <<'SH'
#!/bin/bash
printf 'path=%s\n' "$PATH" >"$XCAT_TEST_LOG"
printf 'arguments=%s\n' "$*" >>"$XCAT_TEST_LOG"
SH
    XCAT_BMC_SUPPORT_DIR="$support_dir" \
        XCAT_BMC_SETUP_IMPLEMENTATION="$BATS_TEST_TMPDIR/implementation" \
        XCAT_TEST_LOG="$log" \
        run /bin/bash "$wrapper" first second
    [ "$status" -eq 0 ]
    grep -q "^path=$support_dir:" "$log"
    grep -qx 'arguments=first second' "$log"
}
