#!/usr/bin/env bash

# Answer "apt-cache policy" as apt does, with translated labels unless LC_ALL or LANG is C.
#
#	$@	Package names. The names in APT_UNKNOWN (default "missing") are unknown to apt, and
#		"nocandidate" is known with no candidate. apt-cache fails after it reports the
#		package in APT_FAIL_AFTER.
apt-cache()
{
    [ "$1" = policy ] || return 1
    shift
    local installed='Installed:' candidate='Candidate:' package
    if [ "${LC_ALL:-${LANG:-}}" != C ]; then
        installed='已安装：'
        candidate='候选：'
    fi
    for package in "$@"; do
        case " ${APT_UNKNOWN:-missing} " in
        *" $package "*) continue ;;
        esac
        case "$package" in
        nocandidate) printf '%s:\n  %s (none)\n  %s (none)\n' "$package" "$installed" "$candidate" ;;
        *) printf '%s:\n  %s (none)\n  %s 1.0-1\n  Version table:\n     1.0-1 500\n' \
            "$package" "$installed" "$candidate" ;;
        esac
        [ "$package" != "${APT_FAIL_AFTER:-}" ] || return 100
    done
}
