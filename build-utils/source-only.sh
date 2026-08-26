#!/bin/bash

# Shared source-only build decisions used by makerpm and buildcore.sh.

function xcat_source_only {
    [ "$SRCONLY" = "1" -o "$SRCONLY" = "yes" ]
}

function xcat_configure_rpm_build_mode {
    local osname="$1"

    if xcat_source_only; then
        if [ "$osname" = "AIX" ]; then
            echo "Error: SRCONLY is not supported on AIX."
            return 1
        fi
        SPECBUILD="-bs"
        TARBUILD="-ts"
    else
        SPECBUILD="-ba"
        TARBUILD="-ta"
    fi
}

function xcat_announce_build {
    if [ "$SPECBUILD" = "-bs" ]; then
        echo "Building $RPMROOT/SRPMS/$1-snap*.src.rpm $EMBEDTXT..."
    else
        echo "Building $2 $EMBEDTXT..."
    fi
}

function xcat_rpmbuild_spec {
    rpmbuild $QUIET "$SPECBUILD" "$@"
}

function xcat_rpmbuild_tar {
    rpmbuild $QUIET "$TARBUILD" "$@"
}

function xcat_require_binary_build {
    local package="$1"

    if xcat_source_only; then
        echo "Error: SRCONLY is not supported for $package."
        return 1
    fi
}
