#!/bin/sh
# EPL license http://www.eclipse.org/legal/epl-v10.html

# Shared POSIX shell helpers for the ospkgs and otherpkgs postscripts.

xcat_find_rpm_package_manager()
{
    if [ -x "${1:-/usr/bin}/dnf" ]; then
        printf '%s\n' dnf
    elif [ -x "${1:-/usr/bin}/yum" ]; then
        printf '%s\n' yum
    else
        return 1
    fi
}

# Keep the marker assignment last so callers know the whole library loaded.
# shellcheck disable=SC2034
XCATPKGUTILS_LOADED=1
