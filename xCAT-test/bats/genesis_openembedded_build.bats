#!/usr/bin/env bats
#
# oe/build runs kas once for each Genesis architecture it is given. kas is a scratch script
# that logs its arguments.

load 'helpers/shell_source'

setup()
{
    BUILD="$(require_repo_file 'xCAT-genesis-base/oe/build')"
    OE_DIR="$(cd "$(dirname "$BUILD")" && pwd)"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$XCAT_TEST_KAS_LOG"\n' >"$BATS_TEST_TMPDIR/kas"
    chmod 0755 "$BATS_TEST_TMPDIR/kas"
    export KAS="$BATS_TEST_TMPDIR/kas"
    export XCAT_TEST_KAS_LOG="$BATS_TEST_TMPDIR/kas.log"
    export XCAT_GENESIS_WORK_DIR="$BATS_TEST_TMPDIR/work"
    : >"$XCAT_TEST_KAS_LOG"
}

@test "the build reports each supported architecture once" {
    run "$BUILD" --list-architectures
    [ "$status" -eq 0 ]
    [ "$output" = 'aarch64
armv7hf
riscv64
s390x
x86
x86_64
ppc64
ppc64le' ]
}

@test "the build accepts s390x and runs its kas configuration once" {
    run "$BUILD" s390x
    [ "$status" -eq 0 ]
    [ "$(cat "$XCAT_TEST_KAS_LOG")" = "build $OE_DIR/kas/s390x.yml" ]
}

@test "the build rejects an unsupported architecture and takes names literally" {
    run "$BUILD" not-an-architecture
    [ "$status" -eq 2 ]
    run "$BUILD" 'x86*'
    [ "$status" -eq 2 ]
    [ ! -s "$XCAT_TEST_KAS_LOG" ]
}
