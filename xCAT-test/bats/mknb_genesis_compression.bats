#!/usr/bin/env bats

setup()
{
    [ "$(uname -s)" = Linux ] || skip 'Genesis compression requires Linux namespaces'
    fixture="$BATS_TEST_TMPDIR/build"
    [ -n "$BATS_TEST_TMPDIR" ] || return 1
    mkdir -p "$fixture"/{source/share/xcat/netboot/genesis/x86_64/fs,root/.ssh,etc/xcat,config,tftp,bin,unpacked}
    printf 'fixture payload\n' > "$fixture/source/share/xcat/netboot/genesis/x86_64/fs/payload"
    printf 'fixture kernel\n' > "$fixture/source/share/xcat/netboot/genesis/x86_64/kernel"
    printf 'fixture public key\n' > "$fixture/root/.ssh/id_rsa.pub"
    mkdir -p "$fixture/usr-bin"
    for command in /usr/bin/*; do
        [ "${command##*/}" = lzma ] || ln -s "/tmp/real-bin/${command##*/}" "$fixture/usr-bin/"
    done
    cp /usr/bin/xz "$fixture/usr-bin/lzma"
}

build_image()
{
    bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
        --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
        --bind "$fixture" /tmp/fixture --bind "$fixture/root" /root \
        --bind "$fixture/etc" /etc --chdir /tmp/fixture \
        --ro-bind /usr/bin /tmp/real-bin --ro-bind "$fixture/usr-bin" /usr/bin \
        --setenv PATH /tmp/fixture/bin:/usr/bin:/bin \
        perl /tmp/source/xCAT-test/bats/fixtures/mknb-compress.pl "$1"
}

check_payload()
{
    local image="$1" compression="$2" mode="$3"
    [ "$(stat -c '%a' "$image")" = "$mode" ]
    if [ "$compression" = xz ]; then
        xz --format=lzma --test "$image"
    fi
    (cd "$fixture/unpacked" && "$compression" -dc "$image" | cpio -id)
    [ "$(cat "$fixture/unpacked/payload")" = 'fixture payload' ]
    [ "$(cat "$fixture/unpacked/.ssh/authorized_keys")" = 'fixture public key' ]
    [ "$(stat -c '%a' "$fixture/unpacked/.ssh/authorized_keys")" = 600 ]
    [ "$(cat "$fixture/tftp/xcat/genesis.kernel.x86_64")" = 'fixture kernel' ]
    [ "$(find "$fixture/tftp/xcat" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort)" = \
        "$(printf '%s\n' "$(basename "$image")" genesis.kernel.x86_64 ipxe xnba | sort)" ]
}

@test "mknb publishes a complete image with lzma and the caller's umask" {
    run build_image 022
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
    check_payload "$fixture/tftp/xcat/genesis.fs.x86_64.lzma" xz 644
}

@test "mknb publishes LZMA format with xz when lzma is unavailable" {
    chmod 644 "$fixture/usr-bin/lzma"
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

@test "mknb stops if its destination staging directory cannot be created" {
    [ "$(id -u)" -ne 0 ] || skip 'root can write mode-500 directories'
    mkdir -p "$fixture/tftp/xcat"
    printf 'old kernel\n' > "$fixture/tftp/xcat/genesis.kernel.x86_64"
    chmod 500 "$fixture/tftp/xcat"
    run build_image 022
    chmod 700 "$fixture/tftp/xcat"
    [ "$status" -ne 0 ]
    [[ "$output" == *'Failed to create a temporary directory'* ]] || { printf '%s\n' "$output"; return 1; }
    [ "$(find "$fixture/tftp/xcat" -mindepth 1 -maxdepth 1 -printf '%f\n')" = genesis.kernel.x86_64 ]
}

@test "mknb publishes exported Genesis with a separate temporary filesystem" {
    run bwrap --die-with-parent --unshare-net --ro-bind / / --dev /dev --proc /proc \
        --tmpfs /tmp --ro-bind "$BATS_TEST_DIRNAME/../.." /tmp/source \
        --bind "$fixture" /tmp/fixture --setenv TMPDIR /tmp \
        --chdir /tmp sh -c '
            [ "$(stat -c %d /tmp)" != "$(stat -c %d /tmp/fixture)" ] || exit 70
            exec perl /tmp/source/xCAT-test/unit/mknb_genesis_atomic.t /tmp/fixture
        '
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}
