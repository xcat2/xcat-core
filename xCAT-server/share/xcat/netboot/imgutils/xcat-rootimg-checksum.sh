#!/bin/sh

# Callers provide rootimg_fetch_checksum and rootimg_checksum_error for their download command.
# Callers log failures printed for the image URL ($1) and downloaded file ($2).
rootimg_matches_checksum() {
    command -v sha256sum >/dev/null 2>&1 || { echo "this initial ramdisk has no sha256sum to check $1"; return 1; }
    rootimg_fetch_checksum "$1" /tmp/rootimg.sha256 || { rootimg_checksum_error "$1"; return 1; }
    rootimg_sum=$(sha256sum <"$2") || { echo "sha256sum cannot read $2"; return 1; }
    # A download that overlaps packimage can match either the current checksum or the one fetched before it.
    cat /tmp/rootimg.sha256 /tmp/rootimg.sha256.before >/tmp/rootimg.sums 2>/dev/null
    while read -r rootimg_expected rootimg_name; do
        [ "${rootimg_sum%% *}" = "$rootimg_expected" ] && return 0
    done </tmp/rootimg.sums
    echo "$1 does not match $1.sha256"
    return 1
}
