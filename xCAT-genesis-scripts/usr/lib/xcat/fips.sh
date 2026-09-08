#!/bin/sh

# Genesis and postscripts ship separately; keep shared policy aligned with xCAT/postscripts/xcatlib.sh.
xcat_fips_enabled()
{
    grep -q '^1$' "${1:-/proc/sys/crypto/fips_enabled}" 2>/dev/null
}

xcat_fips_state()
{
    if xcat_fips_enabled "$1"; then
        printf '1'
    else
        printf '0'
    fi
}

xcat_dsa_allowed()
{
    [ "$1" = 0 ]
}

xcat_generate_discovery_private_key()
{
    case "$1" in
        1) openssl ecparam -name prime256v1 -genkey -noout -out "$2" ;;
        0) openssl genrsa -out "$2" 1024 ;;
        *) return 1 ;;
    esac
}

xcat_discovery_public_key()
{
    case "$1" in
        1) openssl ec -in "$2" -pubout ;;
        0) openssl rsa -in "$2" -pubout ;;
        *) return 1 ;;
    esac
}
