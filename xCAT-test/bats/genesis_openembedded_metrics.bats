#!/usr/bin/env bats
#
# genesis-metrics runs in the OpenEmbedded Genesis image and records the boot-ready time and
# memory use. oe/report runs on the build host and reports the image sizes with those metrics,
# and the growth against a baseline. Inputs are scratch files named by environment variables.

load 'helpers/shell_source'

INIT_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-init/files'

setup()
{
    METRICS="$(require_repo_file "$INIT_FILES/genesis-metrics")"
    REPORT="$(require_repo_file 'xCAT-genesis-base/oe/report')"
    export XCAT_REGISTRATION_STATUS_FILE="$BATS_TEST_TMPDIR/registration.env"
    export XCAT_MEMINFO_FILE="$BATS_TEST_TMPDIR/meminfo"
    export XCAT_UPTIME_FILE="$BATS_TEST_TMPDIR/uptime"
    runtime="$BATS_TEST_TMPDIR/metrics.env"
    printf 'SCHEMA=1\nSTATE=ACTION_RECEIVED\nDETAIL=Destiny shell\nUPDATED_SECONDS=42\n' \
        >"$XCAT_REGISTRATION_STATUS_FILE"
    printf 'MemTotal:       1048576 kB\nMemFree:         524288 kB\nMemAvailable:   786432 kB\n' \
        >"$XCAT_MEMINFO_FILE"
    printf '45.92 12.34\n' >"$XCAT_UPTIME_FILE"

    image_dir="$BATS_TEST_TMPDIR/image"
    mkdir -p "$image_dir"
    printf 'kernel\n' >"$image_dir/kernel"
    printf 'cpio payload\n' | gzip -c >"$image_dir/initramfs.cpio.gz"
}

EXPECTED_RUNTIME='SCHEMA=1
BOOT_READY_SECONDS=42
CAPTURE_UPTIME_SECONDS=45
MEMORY_TOTAL_KIB=1048576
MEMORY_AVAILABLE_KIB=786432
MEMORY_USED_KIB=262144'

# The value of one NAME=VALUE line of $output.
value()
{
    sed -n "s/^$1=//p" <<<"$output"
}

@test "runtime metrics are collected: boot time and memory use" {
    run "$METRICS"
    [ "$status" -eq 0 ]
    [ "$(sort <<<"$output")" = "$(sort <<<"$EXPECTED_RUNTIME")" ]
}

@test "runtime metrics are stored atomically, complete and readable" {
    run "$METRICS" --output "$runtime"
    [ "$status" -eq 0 ]
    [ "$(cat "$runtime")" = "$EXPECTED_RUNTIME" ]
    [ "$(stat -c %a "$runtime")" = 644 ]
}

@test "image and runtime metrics are reported together" {
    "$METRICS" --output "$runtime"
    run "$REPORT" --runtime "$runtime" x86_64 "$image_dir"
    [ "$status" -eq 0 ]
    [ "$(value ARCHITECTURE)" = x86_64 ]
    [ "$(value KERNEL_BYTES)" = "$(stat -c %s "$image_dir/kernel")" ]
    [ "$(value COMPRESSED_INITRAMFS_BYTES)" = "$(stat -c %s "$image_dir/initramfs.cpio.gz")" ]
    [ "$(value UNPACKED_INITRAMFS_BYTES)" = 13 ]
    [ "$(value BOOT_READY_SECONDS)" = 42 ]
    [ "$(value MEMORY_USED_KIB)" = 262144 ]
}

@test "the report compares against a matching baseline and reports the growth" {
    "$METRICS" --output "$runtime"
    baseline="$BATS_TEST_TMPDIR/baseline.env"
    {
        printf 'SCHEMA=1\nARCHITECTURE=x86_64\n'
        printf 'KERNEL_BYTES=%d\n' $(($(stat -c %s "$image_dir/kernel") - 2))
        printf 'COMPRESSED_INITRAMFS_BYTES=%d\n' $(($(stat -c %s "$image_dir/initramfs.cpio.gz") - 3))
        printf 'UNPACKED_INITRAMFS_BYTES=%d\n' $((13 - 4))
        printf 'BOOT_READY_SECONDS=40\nMEMORY_USED_KIB=250000\n'
    } >"$baseline"
    run "$REPORT" --runtime "$runtime" --baseline "$baseline" x86_64 "$image_dir"
    [ "$status" -eq 0 ]
    [ "$(value KERNEL_BYTES_DELTA)" = 2 ]
    [ "$(value COMPRESSED_INITRAMFS_BYTES_DELTA)" = 3 ]
    [ "$(value UNPACKED_INITRAMFS_BYTES_DELTA)" = 4 ]
    [ "$(value BOOT_READY_SECONDS_DELTA)" = 2 ]
    [ "$(value MEMORY_USED_KIB_DELTA)" = 12144 ]
}
