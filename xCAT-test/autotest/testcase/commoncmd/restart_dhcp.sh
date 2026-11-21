#!/bin/bash
# Restart the DHCPv4 server this management node actually runs.
#
# xCAT's Kea unit is kea-dhcp4 on EL and kea-dhcp4-server on Debian and Ubuntu. The cases probed
# the EL name alone, so the probe was false on Ubuntu and the fallback restarted
# isc-dhcp-server -- which is absent where Kea is the backend. The restart then exited 5 with
# "Unit isc-dhcp-server.service not found" and failed the case.
set -u

UNITS=${XCAT_DHCP4_UNITS:-"kea-dhcp4 kea-dhcp4-server isc-dhcp-server dhcpd"}

# --print-unit names the active unit instead of restarting it, for a caller that asks which
# backend this node runs. A caller testing for Kea must not probe the EL unit name alone.
print_only=no
if [ "${1:-}" = --print-unit ]; then
    print_only=yes
fi

for unit in $UNITS; do
    if systemctl is-active "$unit" >/dev/null 2>&1; then
        if [ "$print_only" = yes ]; then
            printf '%s\n' "$unit"
            exit 0
        fi
        exec systemctl restart "$unit"
    fi
done

echo "no DHCPv4 server is active on this node; tried: $UNITS" >&2
exit 1
