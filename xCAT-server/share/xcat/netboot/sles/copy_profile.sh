#!/bin/sh

if [ -z $1 -o -z $2 ]; then
  cat <<END
Usage: $0 {source profile} {destination profile}

END
exit 1
fi

source=$1
dest=$2

for ext in exlist pkglist postinstall repolist; do
  if [ -r $source.$ext ]; then
    echo cp -b $source.$ext $dest.$ext
    cp -b $source.$ext $dest.$ext
  fi
done

