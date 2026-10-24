#!/usr/bin/env bats
#
# The byte order of a DUID-UUID, as the legacy Genesis image sends it.
#
# doxcat writes a default-duid for the ISC client from the SMBIOS UUID, and makedhcp writes the
# same octets into the DHCPv6 reservation. They have to agree, so this is the reference for both
# the Kea DUID (xCAT-test/unit/dhcp_kea_plugin_intent.t) and what discovery reports into vpd.uuid.
# dodiscovery carries the same expression, and needs xcatd and a network to reach it.

load 'helpers/doxcat_sandbox'

setup()
{
    setup_doxcat
    add_doxcat_link boot0 BROADCAST,MULTICAST,UP ether aa:bb:cc:dd:ee:ff
    mkdir -p "$fixture/sys/devices/virtual/dmi/id"
    leases="$fixture/var/lib/dhclient/dhclient6.leases"
}

# doxcat writes the DUID as escaped octal. Render it as the colon-separated hex that makedhcp
# puts in the reservation, so one DUID can be compared with the other.
sent_duid()
{
    local octets octet duid=

    octets=$(sed -e 's/^default-duid "//' -e 's/";$//' \
        -e 's/\\\\\([0-7][0-7][0-7]\)/\1 /g' "$leases")
    for octet in $octets; do
        duid="$duid:$(printf '%02x' "$((8#$octet))")"
    done
    printf '%s' "${duid#:}"
}

@test "the DUID carries the first three SMBIOS fields in firmware order" {
    printf '00112233-4455-6677-8899-aabbccddeeff\n' \
        >"$fixture/sys/devices/virtual/dmi/id/product_uuid"
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ "$(sent_duid)" = 00:04:33:22:11:00:55:44:77:66:88:99:aa:bb:cc:dd:ee:ff ]
}

@test "a machine with no SMBIOS UUID sends no DUID-UUID" {
    run_genesis 0 --setenv BOOTIF 01-aa-bb-cc-dd-ee-ff
    [ ! -e "$leases" ]
}
