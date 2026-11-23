#!/bin/sh
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH
umask 077
[ "$(uname -s)" = FreeBSD ] || exit 77
[ "$#" = 2 ] || { printf 'Usage: %s dhcpcd-10.5.2.tar.gz new-output-directory\n' "$0" >&2; exit 2; }
archive=$(realpath "$1")
[ "$(sha256 -q "$archive")" = 6040a01c69a17dc166d350f6dacf8444ab1e1945481bc84ff50d7ca74364b78d ]
[ ! -e "$2" ] && [ ! -L "$2" ]
mkdir -m 0700 "$2"
work=$(realpath "$2")
test_dir=$(CDPATH= cd -P "$(dirname "$0")" && pwd)
source_dir=$(CDPATH= cd -P "$test_dir/../.." && pwd)
tar -xf "$archive" -C "$work"
cd "$work/dhcpcd-10.5.2"
cp src/bpf.c "$work/bpf-baseline.c"
patch -p1 --batch < "$source_dir/xCAT-server/share/xcat/install/freebsd/patches/dhcpcd-10.5.2-ipoib.patch" > "$work/patch.log"
./configure --disable-ipv6 --disable-arp --privsepuser=_dhcp > "$work/configure.log"
for version in candidate baseline; do
    bpf_source=src/bpf.c
    [ "$version" != baseline ] || bpf_source=$work/bpf-baseline.c
    cc -Wall -Wextra -Werror -D_GNU_SOURCE -DINET -I. -Isrc -Ivendor \
        "$test_dir/freebsd_ipoib_bpf.c" "$bpf_source" -lpcap -o "$work/$version"
done
"$work/candidate" > "$work/candidate.tap"
cat "$work/candidate.tap"
status=0
"$work/baseline" > "$work/baseline.tap" || status=$?
[ "$status" = 1 ]
awk '$1=="not" && $2=="ok" {if ($3<11 || $3>14) bad=1; n++}
    END {exit (bad || n!=4)}' "$work/baseline.tap"
printf '# Baseline rejects all four IPoIB framing and filter assertions.\n'
cc -shared -fPIC -Wall -Wextra -Werror "$test_dir/freebsd_ipoib_link.c" -o "$work/ipoib-link.so"
printf '# Test-only link metadata fixture: %s/ipoib-link.so\n' "$work"
