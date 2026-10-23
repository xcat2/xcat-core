#!/bin/sh
set -eu

# Preserve timestamps so checksum coverage does not depend on signing within one clock tick.
timestamps=$(mktemp -d)
trap 'rm -rf -- "$timestamps"' EXIT
index=0
for package do
    if [ -f "$package" ]; then
        touch -r "$package" "$timestamps/$index"
    fi
    index=$((index + 1))
done

"$XCAT_TEST_RPMSIGN" "$@"

index=0
for package do
    if [ -f "$timestamps/$index" ]; then
        touch -r "$timestamps/$index" "$package"
    fi
    index=$((index + 1))
done
