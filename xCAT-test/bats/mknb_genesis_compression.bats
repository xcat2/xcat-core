#!/usr/bin/env bats

setup()
{
    fixture="$BATS_TEST_TMPDIR/build"
    [ -n "$BATS_TEST_TMPDIR" ] || return 1
    mkdir -p "$fixture"/{source/share/xcat/netboot/genesis/x86_64/fs,root/.ssh,etc/xcat,config,tftp,bin,unpacked}
    printf 'fixture payload\n' > "$fixture/source/share/xcat/netboot/genesis/x86_64/fs/payload"
    printf 'fixture kernel\n' > "$fixture/source/share/xcat/netboot/genesis/x86_64/kernel"
    printf 'fixture public key\n' > "$fixture/root/.ssh/id_rsa.pub"
}

build_image()
{
    bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
        --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
        --bind "$fixture" /tmp/fixture --bind "$fixture/root" /root \
        --bind "$fixture/etc" /etc --chdir /tmp/fixture \
        --setenv PATH /tmp/fixture/bin:/usr/bin:/bin \
        perl /tmp/source/xCAT-test/bats/fixtures/mknb-compress.pl "$1"
}

check_payload()
{
    local image="$1" compression="$2" mode="$3"
    [ "$(stat -c '%a' "$image")" = "$mode" ]
    (cd "$fixture/unpacked" && "$compression" -dc "$image" | cpio -id)
    [ "$(cat "$fixture/unpacked/payload")" = 'fixture payload' ]
    [ "$(cat "$fixture/unpacked/.ssh/authorized_keys")" = 'fixture public key' ]
    [ "$(stat -c '%a' "$fixture/unpacked/.ssh/authorized_keys")" = 600 ]
    [ "$(cat "$fixture/tftp/xcat/genesis.kernel.x86_64")" = 'fixture kernel' ]
    [ "$(find "$fixture/tftp/xcat" -maxdepth 1 -type f | wc -l)" -eq 2 ]
}

@test "mknb publishes a complete LZMA image with the caller's umask" {
    run build_image 022
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    check_payload "$fixture/tftp/xcat/genesis.fs.x86_64.lzma" xz 644
}

@test "mknb falls back to gzip and removes the failed LZMA staging file" {
    printf '#!/bin/sh\nprintf partial\nexit 42\n' > "$fixture/bin/lzma"
    cp "$fixture/bin/lzma" "$fixture/bin/xz"
    chmod +x "$fixture/bin/lzma" "$fixture/bin/xz"
    run build_image 027
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    [[ "$output" == *'failed, falling back to gzip'* ]]
    check_payload "$fixture/tftp/xcat/genesis.fs.x86_64.gz" gzip 640
}
