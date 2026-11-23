#!/bin/sh
set -eu

fail()
{
    printf 'xCAT native resolver build: %s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 0 ] || fail 'Run inside the prepared FreeBSD build root without arguments'
PATH=/sbin:/bin:/usr/sbin:/usr/bin
LC_ALL=C
TMPDIR=/work/tmp
CC=/usr/bin/cc
CC_FOR_BUILD=/usr/bin/cc
CFLAGS='-O2 -pipe -Wno-error'
CPPFLAGS=
LDFLAGS=
export PATH LC_ALL TMPDIR CC CC_FOR_BUILD CFLAGS CPPFLAGS LDFLAGS
umask 022
inputs=/work/recipe-inputs
output=/work/pkg-build
[ "$(uname -s):$(uname -m)" = FreeBSD:amd64 ] || fail 'FreeBSD amd64 is required'
[ "$(id -u)" = 0 ] || fail 'Run as root inside the build root'
[ "$(sha256 -q /usr/bin/cc)" = f409cf3a9253d302818bc1283320f5426df92c2c660711012fb25a054511fb62 ] || fail 'Unsupported release compiler'
for name in "$output" /inputs /work/f3 /work/empty-v3 /work/postscript-packages-v1 /work/freebsd-pkg-resolve; do
    [ ! -e "$name" ] && [ ! -L "$name" ] || fail "Build output already exists: $name"
done
if [ -d /var/db/pkg ] && [ ! -L /var/db/pkg ]; then
    rmdir /var/db/pkg || fail 'The build root contains package state'
fi
[ ! -e /var/db/pkg ] && [ ! -L /var/db/pkg ] || fail 'The build root contains package state'
while read -r pin name; do
    [ -f "$inputs/$name" ] && [ ! -L "$inputs/$name" ] || fail "Missing input: $name"
    [ "$(sha256 -q "$inputs/$name")" = "$pin" ] || fail "Input checksum mismatch: $name"
done <<'INPUTS'
b1f940c5ffbcb91cb4a34d59dffa14db4a3f9c55928964b9e66eb2da1180c6d1 freebsd-pkg-2.6.2_GH0.tar.gz
bbf7bcde8cab52ccca7918aacb75ecaac20b0444a77ce524beb4aa25b7ee6614 ports-mgmt/pkg/Makefile
8c406d14960aa820b6a921a0757cd87a6322769197cae0e19a889650adb905dd ports-mgmt/pkg/distinfo
504b71ba14a3782a5f2273fc78315768e73c4e62392b6e7c6ffd12f8f6922d0d ports-mgmt/pkg/files/patch-libpkg_libpkg.ver
1cbff9a2e84d55626f2d9d5580ed2d691b6f7e13ca7cb4d716789ca93bb098da ports-mgmt/pkg/files/patch-src_Makefile.autosetup
b00ff33bef3670751f6f13dd8f9257e6e3e235fb80ff703a4c26edabc0f797f2 freebsd-pkg-resolve.c
24d8b4751de27ef724291f788874dbfd2df07710eeb18fd7fcc54e02546e2bf3 freebsd-pkg-native.c
0630e67508f619e1eabaaad91455ac910d0886b00e039aa7fa0beb2633ac7090 pkg-2.6.2-apply.patch
INPUTS
# Fixed source paths preserve the qualified binary checksum.
mkdir -p "$output/source" /work/tmp /inputs/pkg
tar -xpf "$inputs/freebsd-pkg-2.6.2_GH0.tar.gz" -C "$output/source"
source=$output/source/pkg-2.6.2
cd "$source"
for patch_name in patch-libpkg_libpkg.ver patch-src_Makefile.autosetup; do
    patch -f -F 0 -p0 -i "$inputs/ports-mgmt/pkg/files/$patch_name"
done
patch -f -F 0 -p1 -i "$inputs/pkg-2.6.2-apply.patch"
[ -z "$(find . -name '*.rej' -print)" ]
/usr/bin/cc -o jimsh0 autosetup/jimsh0.c
/bin/sh ./configure --debug --prefix=/usr/local
for directory in external compat libpkg/repo libpkg; do
    /usr/bin/make -j1 -C "$directory" all
done
cp -p libpkg/pkg.h /inputs/pkg.h
cp -p libpkg/pkg/vec.h /inputs/pkg/vec.h
mkdir -p /inputs/native /work/f3/libpkg /work/empty-v3 /work/postscript-packages-v1
find . -type f -name '*.h' | sort > "$output/headers.list"
tar -cf "$output/headers.tar" -T "$output/headers.list"
tar -xpf "$output/headers.tar" -C /inputs/native
cp -p libpkg/pkg.c libpkg/pkgdb_iterator.c /work/f3/libpkg/
for name in pkgdb_iterator pkg; do
    /usr/bin/cc -O2 -pipe -DHAVE_CONFIG_H '-DPREFIX="/usr/local"' \
        -Wno-pointer-sign -Wno-missing-field-initializers -Wno-sign-compare \
        -I/inputs -I/inputs/native -I/inputs/native/compat -I/inputs/native/libpkg \
        -I/inputs/native/external/include -I/inputs/native/external/uthash \
        -I/inputs/native/external/libucl/include -I/inputs/native/external/sqlite \
        -c /work/f3/libpkg/$name.c -o /work/f3/$name.o
done
cp -p libpkg/libpkg_flat.a /work/f3/libpkg_flat.a
ar r /work/f3/libpkg_flat.a /work/f3/pkgdb_iterator.o /work/f3/pkg.o
ranlib /work/f3/libpkg_flat.a
sha256 /work/f3/libpkg_flat.a
[ "$(sha256 -q /work/f3/libpkg_flat.a)" = 70fa979077ff602054dae21e828f4430341ebe22cf2464a859bb6f58e9f926f3 ]
cp -p /work/f3/libpkg_flat.a /inputs/libpkg_flat.a
cp -p "$inputs/freebsd-pkg-resolve.c" /work/empty-v3/main.c
cp -p "$inputs/freebsd-pkg-native.c" /work/postscript-packages-v1/adapter.c
/usr/bin/cc -std=c11 -Wall -Wextra -Werror -DXCAT_PKG_TARGET_VERSION=20602 \
    -I/inputs -c /work/empty-v3/main.c -o /work/empty-v3/main.o
/usr/bin/cc -std=c11 -Wall -Wextra -Werror -DXCAT_PKG_TARGET_VERSION=20602 \
    -I/inputs -I/inputs/native -I/inputs/native/compat -I/inputs/native/libpkg \
    -I/inputs/native/external/include -I/inputs/native/external/uthash \
    -I/inputs/native/external/libucl/include -I/inputs/native/external/sqlite \
    -c /work/postscript-packages-v1/adapter.c -o /work/adapter.o
sha256 /work/adapter.o
[ "$(sha256 -q /work/adapter.o)" = 5c79a8bb6296bb10f5349d2955ef3d86eb338e7a05753d3febee5a90898f5ae1 ]
/usr/bin/cc /work/empty-v3/main.o /work/adapter.o /inputs/libpkg_flat.a \
    -Wl,--fatal-warnings -Wl,--as-needed /lib/libelf.so.2 /lib/libm.so.5 \
    /lib/libthr.so.3 /usr/lib/libarchive.so.7 /usr/lib/libbz2.so.4 /lib/libz.so.6 \
    /usr/lib/liblzma.so.5 /usr/lib/libprivatezstd.so.5 /lib/libutil.so.10 \
    /usr/lib/libssl.so.35 /lib/libcrypto.so.35 /lib/libmd.so.7 \
    -Wl,-Map,/work/empty-v3/main.map -o /work/empty-v3/main
sha256 /work/empty-v3/main
[ "$(sha256 -q /work/empty-v3/main)" = ad1be19a9491ac9b34c5a203c6c90d70907949c6ddb548a168034b64f8e87be9 ]
/work/empty-v3/main -C /work/unused-config -v
ldd /work/empty-v3/main > "$output/resolver.ldd"
! grep -E 'not found|libpkg' "$output/resolver.ldd"
[ ! -e /var/db/pkg ]
install -m 0555 /work/empty-v3/main /work/freebsd-pkg-resolve
printf 'Built /work/freebsd-pkg-resolve\n'
