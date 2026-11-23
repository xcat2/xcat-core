#!/bin/sh

set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL

fail()
{
    printf 'xCAT FreeBSD runtime: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 2 ] || fail 'Usage: stage-pkgbase-runtime.sh ram-root pkg-archive'
[ "$(uname -s)" = FreeBSD ] && [ "$(uname -m)" = amd64 ] || fail 'FreeBSD amd64 is required'
case "$(freebsd-version -u)" in
    15.1-RELEASE|15.1-RELEASE-p[0-9]*) ;;
    *) fail 'FreeBSD 15.1-RELEASE is required' ;;
esac
[ "$(id -u)" -eq 0 ] || fail 'Root is required'

runtime_root=$(realpath "$1")
pkg_archive=$(realpath "$2")
[ "$runtime_root" != / ] && [ "$runtime_root" = "$1" ] || fail 'Use a canonical RAM-root path other than /'
case "$runtime_root" in *[!A-Za-z0-9_./+-]*) fail 'Unsupported RAM-root path' ;; esac
[ -f "$pkg_archive" ] && [ ! -L "$2" ] || fail 'The pkg archive must be a regular file'
[ "$(sha256 -q "$pkg_archive")" = ae22a209d68078786f8804e771b1aa484730d9591d6254b63f8904db3cba86c1 ] ||
    fail 'Unsupported FreeBSD 15.1 pkg archive checksum'

check_native()
{
    [ -f "$runtime_root/$1" ] && [ ! -L "$runtime_root/$1" ] || fail "Missing native runtime file: $1"
    [ "$(sha256 -q "$runtime_root/$1")" = "$2" ] || fail "Unsupported native runtime checksum: $1"
}

check_native usr/sbin/bsdinstall 668e0d3931d7846662ba8558e50e825edd56e0e6808bf4aa25b3252f0bf64ff8
check_native usr/libexec/bsdinstall/script 1683193f5d36338d3a3db10322a0953222bcee357715819e0f8996e48c192788
check_native usr/libexec/bsdinstall/pkgbase 502e4f8330e06f6c939a074315bf1b70fbd7b68e8f17e91cdaf12147c81ae778
check_native usr/libexec/flua 146b08a087f8b2c63e0246306e525ad80ee273f8f6ce0012b5098ebd171dcda4
for runtime_dir in tmp var var/db usr usr/local etc etc/pkg; do
    [ -d "$runtime_root/$runtime_dir" ] && [ ! -L "$runtime_root/$runtime_dir" ] ||
        fail "Missing or symlinked RAM-root directory: $runtime_dir"
done
for absent_path in var/db/pkg usr/local/sbin/pkg usr/local/sbin/pkg-static usr/local/etc/pkg; do
    [ ! -e "$runtime_root/$absent_path" ] && [ ! -L "$runtime_root/$absent_path" ] ||
        fail "Runtime package state already exists: $absent_path"
done

stage_work=$(mktemp -d "$runtime_root/tmp/xcat-pkgstage.XXXXXX")
cleanup()
{
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$result" -eq 0 ]; then
        rm -rf "$stage_work"
    else
        printf 'Runtime staging stopped. Diagnostics: %s\n' "$stage_work" >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
mkdir "$stage_work/empty-repositories"
cp "$pkg_archive" "$stage_work/pkg.pkg"
pkg_archive=$stage_work/pkg.pkg
[ "$(sha256 -q "$pkg_archive")" = ae22a209d68078786f8804e771b1aa484730d9591d6254b63f8904db3cba86c1 ] ||
    fail 'The staged pkg archive checksum does not match'
tar -xOf "$pkg_archive" /usr/local/sbin/pkg-static > "$stage_work/pkg-static"
[ "$(sha256 -q "$stage_work/pkg-static")" = d75db8494ddab4a03fa8d4187305414fcd88ad64a9a76f326e829e9b32ed248b ] ||
    fail 'The native pkg-static checksum does not match'
chmod 0555 "$stage_work/pkg-static"

native_pkg()
{
    env -i PATH="$PATH" LC_ALL=C \
        timeout -k 5 60 "$stage_work/pkg-static" --rootdir "$runtime_root" \
        -C /dev/null --repo-conf-dir "$stage_work/empty-repositories" \
        -o PKG_ENABLE_PLUGINS=false -o PKG_TRIGGERS_ENABLE=false -o RUN_SCRIPTS=false \
        -o REPO_AUTOUPDATE=false -o IGNORE_OSVERSION=false -o HANDLE_RC_SCRIPTS=false \
        -o ABI=FreeBSD:15:amd64 -o OSVERSION=1501000 -o SYSLOG=false "$@"
}

[ "$(env -i PATH="$PATH" LC_ALL=C timeout -k 5 30 "$stage_work/pkg-static" -v)" = 2.6.2 ] ||
    fail 'The native pkg client version does not match'
env -i PATH="$PATH" LC_ALL=C timeout -k 5 30 chroot "$runtime_root" /usr/libexec/flua \
    -e 'assert(require("posix.unistd")); assert(require("posix.sys.wait"))' \
    > "$stage_work/flua.log" 2>&1 || fail 'The RAM-root flua dependencies do not load'
native_pkg add "$pkg_archive" > "$stage_work/pkg-add.log" 2>&1 || fail 'Offline pkg registration failed'
native_pkg -N > "$stage_work/pkg-activation.log" 2>&1 || fail 'The RAM-root pkg database is not activated'
[ "$(native_pkg query -a '%n-%v')" = pkg-2.6.2_1 ] || fail 'Unexpected RAM-root package registration'
check_native usr/local/sbin/pkg-static d75db8494ddab4a03fa8d4187305414fcd88ad64a9a76f326e829e9b32ed248b

printf 'FreeBSD: { enabled: no }\nFreeBSD-base: { enabled: no }\n' > "$runtime_root/etc/pkg/FreeBSD.conf"
chmod 0444 "$runtime_root/etc/pkg/FreeBSD.conf"
printf 'Staged native pkg 2.6.2_1 in %s\n' "$runtime_root"
