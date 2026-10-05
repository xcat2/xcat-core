#!/bin/sh

xcat_fips_enabled()
{
    grep -q '^1$' "${1:-/proc/sys/crypto/fips_enabled}" 2>/dev/null
}

xcat_fips_state()
{
    if xcat_fips_enabled "${1:-}"; then
        printf '1'
    else
        printf '0'
    fi
}

xcat_dsa_allowed()
{
    [ "$1" = 0 ]
}
