#!/usr/bin/env bats
#
# Genesis extensions are signed squashfs images. oe/scripts/sign-extension signs a manifest,
# oe/export-extension exports a signed bundle, and genesis-sysext verifies and installs an
# extension in the running image. systemd-sysext and genesis-status are shell functions
# written to a scratch PATH; they log their arguments.

load 'helpers/shell_source'

EXT_FILES='xCAT-genesis-base/oe/meta-xcat-genesis/recipes-core/xcat-genesis-extensions/files'

setup()
{
    command -v openssl >/dev/null || skip 'openssl is required'
    command -v jq >/dev/null || skip 'jq is required'
    LOADER="$(require_repo_file "$EXT_FILES/genesis-sysext")"
    SIGNER="$(require_repo_file 'xCAT-genesis-base/oe/scripts/sign-extension')"
    EXPORTER="$(require_repo_file 'xCAT-genesis-base/oe/export-extension')"

    root="$BATS_TEST_TMPDIR"
    mkdir -p "$root/bin" "$root/keys" "$root/run"
    image="$root/xcat-smoke.squashfs-zst"
    manifest="$root/xcat-smoke.manifest.json"
    signature="$root/xcat-smoke.sig"
    private_key="$root/private.pem"
    public_key="$root/keys/xcat-release.pem"
    printf 'extension payload\n' >"$image"
    printf 'ID=xcat-genesis\nVERSION_ID=0.1\n' >"$root/os-release"
    : >"$root/commands.log"
    : >"$root/status.log"
    printf '#!/bin/sh\nprintf "systemd-sysext %%s\\n" "$*" >>"$XCAT_TEST_LOG"\n' >"$root/bin/systemd-sysext"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$XCAT_STATUS_LOG"\n' >"$root/bin/genesis-status"
    chmod 0755 "$root/bin/systemd-sysext" "$root/bin/genesis-status"

    openssl genpkey -algorithm ED25519 -out "$private_key" 2>/dev/null
    openssl pkey -in "$private_key" -pubout -out "$public_key"
    hash="$(sha256sum -- "$image" | cut -c1-64)"
    write_manifest "$manifest" '.'
    "$SIGNER" "$manifest" "$private_key" "$signature"

    export PATH="$root/bin:$PATH"
    export XCAT_GENESIS_EXTENSION_KEY_DIR="$root/keys"
    export XCAT_GENESIS_EXTENSION_RUN_DIR="$root/run"
    export XCAT_GENESIS_OS_RELEASE="$root/os-release"
    export XCAT_GENESIS_STATUS_COMMAND="$root/bin/genesis-status"
    export XCAT_GENESIS_UNAME_M=x86_64
    export XCAT_GENESIS_UNAME_R=6.18.24-test
    export XCAT_TEST_LOG="$root/commands.log"
    export XCAT_STATUS_LOG="$root/status.log"
}

# Write a manifest for $image, changed by a jq filter.
write_manifest()
{
    local path="$1" filter="$2"
    jq -n --arg sha "$hash" '{
        architecture: "x86_64", capabilities: ["diagnostic.smoke"], genesis_release: "0.1",
        kernel_modules: false, kernel_release: null, key_id: "xcat-release",
        license_class: "open", name: "xcat-smoke", pci_ids: [], schema: 1,
        sha256: $sha, version: "1.0"
    }' | jq -S "$filter" >"$path"
}

# Write and sign a changed manifest, then verify it against $image.
verify_changed()
{
    local name="$1" filter="$2"
    write_manifest "$root/$name.json" "$filter"
    "$SIGNER" "$root/$name.json" "$private_key" "$root/$name.sig"
    /bin/bash "$LOADER" verify "$root/$name.json" "$image" "$root/$name.sig"
}

@test "the extension manifest is signed" {
    [ -s "$signature" ]
}

@test "the built extension exports as a signed bundle with its key and checksums" {
    stem=xcat-genesis-extension-smoke-xcat-genesis-x86-64
    machine_dir="$root/deploy/images/xcat-genesis-x86-64"
    mkdir -p "$machine_dir"
    cp "$image" "$machine_dir/$stem.sysext.squashfs-zst"
    cp "$manifest" "$machine_dir/$stem.sysext.manifest.json"
    run "$EXPORTER" x86_64 xcat-genesis-extension-smoke "$root/deploy" \
        "$private_key" "$public_key" "$root/bundle"
    [ "$status" -eq 0 ]
    [ -f "$root/bundle/extensions/$stem.squashfs-zst" ]
    [ -f "$root/bundle/extensions/$stem.manifest.json" ]
    [ -f "$root/bundle/extensions/$stem.sig" ]
    [ -f "$root/bundle/extension-keys/xcat-release.pem" ]
    (cd "$root/bundle" && sha256sum -c SHA256SUMS >/dev/null)
}

@test "a valid extension is accepted" {
    run /bin/bash "$LOADER" verify "$manifest" "$image" "$signature"
    [ "$status" -eq 0 ]
}

@test "i586, armv7l and s390x runtimes use their extension identities" {
    XCAT_GENESIS_UNAME_M=i586 verify_changed x86 '.architecture = "x86"'
    XCAT_GENESIS_UNAME_M=armv7l verify_changed armv7hf '.architecture = "armv7hf"'
    XCAT_GENESIS_UNAME_M=s390x verify_changed s390x '.architecture = "s390x"'
}

@test "a valid extension is installed under its manifest name, and extensions are refreshed" {
    run /bin/bash "$LOADER" install "$manifest" "$image" "$signature"
    [ "$status" -eq 0 ]
    [ -f "$root/run/xcat-smoke.raw" ]
    grep -qx 'systemd-sysext refresh' "$root/commands.log"
}

@test "loading a valid extension directory publishes the active and ready states" {
    run /bin/bash "$LOADER" load-all "$root"
    [ "$status" -eq 0 ]
    grep -qx 'extensions RUNNING Verifying Genesis extensions' "$root/status.log"
    grep -qx 'extensions READY Genesis extensions loaded' "$root/status.log"
}

@test "an invalid signature is rejected" {
    printf '%064d' 0 | tr 0 x >"$root/bad.sig"
    run /bin/bash "$LOADER" verify "$manifest" "$image" "$root/bad.sig"
    [ "$status" -ne 0 ]
    [[ "$output" == *'extension signature verification failed'* ]]
}

@test "a wrong architecture, release, digest or kernel ABI is rejected" {
    run verify_changed arch '.architecture = "riscv64"'
    [ "$status" -ne 0 ]
    [[ "$output" == *'extension architecture riscv64 does not match x86_64'* ]]
    run verify_changed release '.genesis_release = "9.9"'
    [ "$status" -ne 0 ]
    [[ "$output" == *'extension release 9.9 does not match 0.1'* ]]
    run verify_changed digest ".sha256 = \"$(printf '%064d' 0)\""
    [ "$status" -ne 0 ]
    [[ "$output" == *'extension digest does not match'* ]]
    run verify_changed abi '.kernel_modules = true | .kernel_release = "0.0-wrong"'
    [ "$status" -ne 0 ]
    [[ "$output" == *'extension kernel release does not match'* ]]
}

@test "a linked manifest is rejected" {
    ln -s "$manifest" "$root/linked.json"
    run /bin/bash "$LOADER" verify "$root/linked.json" "$image" "$signature"
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid extension input: $root/linked.json"* ]]
}

@test "an empty extension directory is rejected, with a structured recovery status" {
    mkdir -p "$root/empty"
    run /bin/bash "$LOADER" load-all "$root/empty"
    [ "$status" -ne 0 ]
    grep -q '^extensions FAILED no extension manifests found in:' "$root/status.log"
    grep -q 'CODE=EXTENSION_VERIFICATION_FAILED .*RECOVERY=Check extension images, manifests, signatures, and trusted keys' \
        "$root/status.log"
}
