#!/usr/bin/env bats
#
# oe/export copies an OpenEmbedded Genesis image out of a Yocto deploy directory, with its
# SBOM, its VEX report, a format manifest and SHA256SUMS. The deploy directory here is a
# scratch tree in the layout Yocto writes.

load 'helpers/shell_source'

setup()
{
    EXPORT="$(require_repo_file 'xCAT-genesis-base/oe/export')"
    machine=xcat-genesis-x86-64
    image="xcat-genesis-image-$machine.rootfs"
    deploy="$BATS_TEST_TMPDIR/deploy"
    out_dir="$BATS_TEST_TMPDIR/export"
    machine_dir="$deploy/images/$machine"
    license_dir="$deploy/licenses/xcat_genesis_x86_64/$image"
    mkdir -p "$machine_dir" "$license_dir"
    printf kernel >"$machine_dir/bzImage"
    printf initramfs >"$machine_dir/$image.cpio.gz"
    printf packages >"$machine_dir/$image.manifest"
    printf '{}' >"$machine_dir/$image.spdx.json"
    printf '{}' >"$machine_dir/$image.vex.json"
    printf licenses >"$license_dir/license.manifest"
}

@test "the image exports, with its SBOM and VEX report" {
    run "$EXPORT" x86_64 "$deploy" "$out_dir"
    [ "$status" -eq 0 ]
    [ -f "$out_dir/image.spdx.json" ]
    [ -f "$out_dir/image.vex.json" ]
}

@test "the export identifies its format and architecture" {
    "$EXPORT" x86_64 "$deploy" "$out_dir"
    [ "$(cat "$out_dir/xcat-genesis.manifest")" = "format=xcat-genesis
version=1
architecture=x86_64" ]
}

@test "the export manifest has a checksum, and all exported checksums verify" {
    "$EXPORT" x86_64 "$deploy" "$out_dir"
    grep -Eq '^[0-9a-f]{64}  xcat-genesis\.manifest$' "$out_dir/SHA256SUMS"
    (cd "$out_dir" && sha256sum -c SHA256SUMS >/dev/null)
}
