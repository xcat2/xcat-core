#!/bin/sh
#
# stage_sn_apt_repo.sh <repository directory> [<os version>]
#
# Write a flat apt index at <repository directory>, so the otherpkgs postscript on a Debian
# service node can install from it.
#
# The postscript builds one source line per directory named in the osimage otherpkglist, in the
# form "deb <type>://<otherpkgdir>/<directory> ./". That trailing "./" is apt's flat layout: it
# reads <directory>/Packages and takes each Filename relative to it. A reprepro tree with
# dists/ and pool/ has no such file, and neither has a directory of loose debs.
#
# <os version> selects one subdirectory when the tree holds one per release, which is how
# xcat-dep stages its debs. Without it, or with no subdirectory whose name starts the os
# version, the whole tree is indexed.
#
# Run this on the management node. The EL cases call createrepo here, which no Debian host has.

set -u

DIR="${1:-}"
OSVER="${2:-}"

if [ -z "$DIR" ]; then
    echo "usage: $0 <repository directory> [<os version>]" >&2
    exit 2
fi
if [ ! -d "$DIR" ]; then
    echo "apt index error: $DIR is not a directory" >&2
    exit 1
fi

scan=.
for sub in "$DIR"/*/; do
    [ -d "$sub" ] || continue
    name=$(basename "$sub")
    case "$OSVER" in
        "$name"*) scan=$name ;;
    esac
done

cd "$DIR" || exit 1
err=$(mktemp) || exit 1
if ! dpkg-scanpackages -m "$scan" > Packages.new 2>"$err"; then
    echo "apt index error: dpkg-scanpackages failed under $DIR/$scan" >&2
    cat "$err" >&2
    rm -f Packages.new "$err"
    exit 1
fi
rm -f "$err"

# An empty index is the failure this guard exists for: apt reports no candidate, and the
# service node install then fails somewhere else entirely.
count=$(grep -c '^Package: ' Packages.new || true)
if [ "$count" -eq 0 ]; then
    echo "apt index error: no deb package under $DIR/$scan" >&2
    rm -f Packages.new
    exit 1
fi

mv -f Packages.new Packages
gzip -9cf Packages > Packages.gz
echo "apt index ok: $count package(s) indexed at $DIR from $scan"
