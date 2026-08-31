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

xcat_is_el_modular_pkgdir()
{
    case "$1" in
        rhel[89]*|rhel1[0-9]*|rhels[89]*|rhels1[0-9]*|\
        centos[89]*|centos1[0-9]*|rocky[89]*|rocky1[0-9]*|\
        alma[89]*|alma1[0-9]*|almalinux[89]*|almalinux1[0-9]*|\
        ol[89]*|ol1[0-9]*)
            return 0
            ;;
    esac

    return 1
}

# shellcheck disable=SC2034
XCATPKGUTILS_LOADED=1
