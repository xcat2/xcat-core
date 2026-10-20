#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
LC_ALL=C
export PATH LC_ALL
umask 022

fail()
{
    printf 'build-dhcpcd: %s\n' "$1" >&2
    exit 1
}

[ "$#" = 2 ] || fail 'Usage: build-dhcpcd.sh dhcpcd-10.5.2.tar.gz output-directory'
[ "$(uname -s):$(uname -m)" = FreeBSD:amd64 ] || fail 'FreeBSD amd64 is required'
case $(freebsd-version -u) in 15.1-RELEASE|15.1-RELEASE-p[0-9]*) ;; *)
    fail 'FreeBSD 15.1-RELEASE is required' ;;
esac
source_archive=$(realpath "$1")
output=$(realpath "$2")
[ -f "$source_archive" ] && [ -d "$output" ] || fail 'Missing source archive or output directory'
source_sha=6040a01c69a17dc166d350f6dacf8444ab1e1945481bc84ff50d7ca74364b78d
[ "$(sha256 -q "$source_archive")" = "$source_sha" ] || fail 'Source archive checksum differs'
[ "$(getent passwd _dhcp | cut -d : -f 3)" = 65 ] || fail 'The native _dhcp account is required'
script_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
patch_file=$script_dir/patches/dhcpcd-10.5.2-ipoib.patch
[ -f "$patch_file" ] || fail 'The IPoIB patch is missing'
package=xcat-dhcpcd-10.5.2_1.pkg
[ ! -e "$output/$package" ] && [ ! -L "$output/$package" ] || fail 'Output package already exists'
work=$(mktemp -d "${TMPDIR:-/tmp}/xcat-dhcpcd.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
tar -xf "$source_archive" -C "$work"
cd "$work/dhcpcd-10.5.2"
patch -p1 --batch < "$patch_file"
./configure --prefix=/usr/local --sbindir=/usr/local/libexec/xcat \
    --libexecdir=/usr/local/libexec/xcat \
    --dbdir=/var/db/xcat-dhcpcd --rundir=/var/run/xcat-dhcpcd \
    --privsepuser=_dhcp --disable-ipv6 --disable-arp --enable-privsep \
    --enable-embedded
make
stage=$work/stage
install -d -m 0755 "$stage/usr/local/libexec/xcat" "$stage/usr/local/share/xcat-dhcpcd"
install -m 0755 src/dhcpcd "$stage/usr/local/libexec/xcat/dhcpcd-ipoib"
install -m 0444 LICENSE "$stage/usr/local/share/xcat-dhcpcd/LICENSE"
{
    printf 'source-sha256=%s\n' "$source_sha"
    printf 'patch-sha256=%s\n' "$(sha256 -q "$patch_file")"
    printf 'freebsd-version=%s\n' "$(freebsd-version -u)"
} > "$stage/usr/local/share/xcat-dhcpcd/build-info"
chmod 0444 "$stage/usr/local/share/xcat-dhcpcd/build-info"
cat > "$work/manifest" <<'MANIFEST'
name: "xcat-dhcpcd"
version: "10.5.2_1"
origin: "net/xcat-dhcpcd"
comment: "FreeBSD IPoIB DHCPv4 client for xCAT"
desc: "dhcpcd with FreeBSD IPoIB BPF support, isolated runtime paths and privilege separation."
maintainer: "xcat-user@lists.sourceforge.net"
www: "https://xcat.org/"
prefix: "/usr/local"
licenselogic: "single"
licenses: ["BSD2CLAUSE"]
files: {
  "/usr/local/libexec/xcat/dhcpcd-ipoib": "-",
  "/usr/local/share/xcat-dhcpcd/LICENSE": "-",
  "/usr/local/share/xcat-dhcpcd/build-info": "-"
}
MANIFEST
pkg create -M "$work/manifest" -r "$stage" -o "$work"
[ -f "$work/$package" ] || fail 'Package creation did not produce the expected archive'
install -m 0644 "$work/$package" "$output/$package"
sha256 "$output/$package"
