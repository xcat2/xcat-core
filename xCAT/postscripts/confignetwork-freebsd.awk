#!/usr/bin/awk -f

function fail(message) {
    failed = 1
    print "confignetwork: " message > "/dev/stderr"
    exit 1
}

function number(value, minimum, maximum) {
    return value ~ /^(0|[1-9][0-9]*)$/ && value + 0 >= minimum && value + 0 <= maximum
}

function interface_name(value) {
    return length(value) <= 15 && value ~ /^[a-z][a-z0-9]*$/ && value != "lo0"
}

function physical(kind) {
    return kind == "ethernet" || kind == "infiniband"
}

function verify_links(all,    nic) {
    for (nic in wanted_interface) {
        if (!all && !physical(wanted_interface[nic]))
            continue
        if (wanted_ib[nic]) {
            if (observed_ib[nic] == "")
                fail("An InfiniBand link address is missing: " nic)
            if (mode != "verify-prior" && wanted_guid[nic] != "" && substr(observed_ib[nic], 37) != wanted_guid[nic])
                fail("InfiniBand port GUID differs: " nic)
            if (all && mode == "verify" && check_carrier != "no" && wanted_addressed[nic] && !observed_carrier[nic])
                fail("InfiniBand link is not active: " nic)
        } else if (physical(wanted_interface[nic]) && !mac_address(ether[nic]))
            fail("An Ethernet link address is missing: " nic)
    }
}

function verify_existing_carrier(    nic) {
    for (nic in wanted_addressed)
        if (wanted_interface[nic] == "infiniband" && observed_interface[nic] && up[nic] == "up" && !observed_carrier[nic])
            fail("InfiniBand link is not active: " nic)
}

function ib_address(value,    octets, count, i, result) {
    value = tolower(value)
    count = split(value, octets, /[.:]/)
    if (count != 20)
        return ""
    for (i = 1; i <= count; i++) {
        if (octets[i] !~ /^[0-9a-f][0-9a-f]?$/)
            return ""
        result = result (i == 1 ? "" : ":") sprintf("%02x", hex_number(octets[i]))
    }
    return result
}

function mac_address(value,    octets, i) {
    if (split(value, octets, ":") != 6)
        return 0
    for (i = 1; i <= 6; i++)
        if (octets[i] !~ /^[0-9a-f][0-9a-f]$/)
            return 0
    return 1
}

function attribute(name,    text, entries, count, i, position, nic, value) {
    text = ENVIRON[name]
    if (length(text) > 65536 || text ~ /[^ -~]/)
        fail("Invalid " name)
    if (text == "")
        return
    count = split(text, entries, ",")
    for (i = 1; i <= count; i++) {
        position = index(entries[i], "!")
        nic = substr(entries[i], 1, position - 1)
        value = substr(entries[i], position + 1)
        if (!position || !interface_name(nic) || value == "" || index(value, "!"))
            fail("Expected interface!value in " name)
        if ((name SUBSEP nic) in attributes)
            fail("Duplicate " name " entry for " nic)
        attributes[name, nic] = value
        interfaces[nic] = 1
    }
}

function ipv4(value,    parts, count, i, result) {
    count = split(value, parts, ".")
    if (count != 4)
        return ""
    result = 0
    for (i = 1; i <= 4; i++) {
        if (!number(parts[i], 0, 255))
            return ""
        result = result * 256 + parts[i]
    }
    return sprintf("%.0f", result)
}

function hex_number(value,    i, result, digit) {
    result = 0
    for (i = 1; i <= length(value); i++) {
        digit = index("0123456789abcdef", substr(value, i, 1)) - 1
        if (digit < 0)
            return -1
        result = result * 16 + digit
    }
    return result
}

function ipv6(value,    sides, count, left, right, nl, nr, i, result, part) {
    value = tolower(value)
    if (value == "" || value ~ /[^0-9a-f:]/ || value ~ /:::/)
        return ""
    count = split(value, sides, "::")
    if (count > 2)
        return ""
    nl = sides[1] == "" ? 0 : split(sides[1], left, ":")
    nr = count == 1 || sides[2] == "" ? 0 : split(sides[2], right, ":")
    if ((count == 1 && nl != 8) || (count == 2 && nl + nr >= 8))
        return ""
    result = ""
    for (i = 1; i <= 8; i++) {
        if (i <= nl)
            part = left[i]
        else if (i > 8 - nr)
            part = right[i - (8 - nr)]
        else
            part = "0"
        if (part == "" || length(part) > 4 || hex_number(part) < 0)
            return ""
        result = result (i == 1 ? "" : ":") sprintf("%04x", hex_number(part))
    }
    return result
}

function address(value, family,    expanded) {
    if (family == "inet") {
        if (ipv4(value) == "" || value ~ /^(0|127|22[4-9]|23[0-9]|24[0-9]|25[0-5])\./)
            fail("Invalid unicast IPv4 address " value)
        return value
    }
    expanded = ipv6(value)
    if (expanded == "" || expanded ~ /^ff/ || expanded == "0000:0000:0000:0000:0000:0000:0000:0000" ||
        expanded == "0000:0000:0000:0000:0000:0000:0000:0001" || expanded ~ /^0000:0000:0000:0000:0000:ffff:/)
        fail("Invalid unicast IPv6 address " value)
    return expanded
}

function prefix(mask, family,    value, bits, remainder) {
    if (family == "inet6") {
        sub(/^\//, "", mask)
        if (!number(mask, 0, 128))
            fail("Invalid IPv6 prefix " mask)
        return mask + 0
    }
    value = ipv4(mask)
    if (value == "")
        fail("Invalid IPv4 netmask " mask)
    bits = 0
    remainder = 4294967295 - value
    while (remainder > 0) {
        if (remainder % 2 != 1)
            fail("Noncontiguous IPv4 netmask " mask)
        remainder = int(remainder / 2)
        bits++
    }
    return 32 - bits
}

function subnet(value, net, bits, family,    a, b, i, take, scale) {
    if (family == "inet")
        return int(ipv4(value) / 2 ^ (32 - bits)) == int(ipv4(net) / 2 ^ (32 - bits))
    split(ipv6(value), a, ":")
    split(ipv6(net), b, ":")
    for (i = 1; bits > 0; i++) {
        take = bits < 16 ? bits : 16
        scale = 2 ^ (16 - take)
        if (int(hex_number(a[i]) / scale) != int(hex_number(b[i]) / scale))
            return 0
        bits -= take
    }
    return 1
}

function network_address(value, bits, family,    parts, i, take) {
    if (family == "inet")
        return ipv4(value) != "" && ipv4(value) % 2 ^ (32 - bits) == 0
    if (ipv6(value) == "")
        return 0
    split(ipv6(value), parts, ":")
    for (i = 1; i <= 8; i++) {
        take = bits < 16 ? bits : 16
        if (hex_number(parts[i]) % 2 ^ (16 - take) != 0)
            return 0
        bits -= take
    }
    return 1
}

function networks(    count, row, fields, n, i, j, position, key, name, bytes) {
    count = ENVIRON["NETWORKS_LINES"]
    if (!number(count, 0, 4096))
        fail("Missing or invalid networks table export")
    for (i = 1; i <= count; i++) {
        row = ENVIRON["NETWORKS_LINE" i]
        bytes += length(row)
        if (row == "" || row ~ /[\r\n\t]/ || bytes > 1048576)
            fail("Invalid networks table export")
        n = split(row, fields, /\|\|/)
        name = ""
        for (j = 1; j <= n; j++) {
            position = index(fields[j], "=")
            key = substr(fields[j], 1, position - 1)
            if (key == "netname")
                name = substr(fields[j], position + 1)
        }
        if (name == "")
            continue
        network_count[name]++
        for (j = 1; j <= n; j++) {
            position = index(fields[j], "=")
            key = substr(fields[j], 1, position - 1)
            if (key ~ /^(net|mask|gateway|mtu|disable)$/)
                network[name, key] = substr(fields[j], position + 1)
        }
    }
}

function options(nic,    text, count, parts, pair, i, key, value) {
    text = attributes["NICEXTRAPARAMS", nic]
    if (text == "")
        return
    count = split(text, parts, / +/)
    for (i = 1; i <= count; i++) {
        if (split(parts[i], pair, "=") != 2 || pair[2] == "")
            fail("Expected key=value in nicextraparams for " nic)
        key = pair[1]
        value = pair[2]
        if ((nic SUBSEP key) in option)
            fail("Duplicate option " key " for " nic)
        if (key == "MTU") {
            if (!number(value, 576, 9216))
                fail("Invalid MTU for " nic)
        } else if (key == "MACADDR" && type[nic] != "ethernet") {
            value = tolower(value)
            if (!mac_address(value) ||
                hex_number(substr(value, 1, 2)) % 2 || value == "00:00:00:00:00:00")
                fail("Invalid unicast MAC address for " nic)
        } else if (key == "IB_DRIVER" && type[nic] == "infiniband") {
            if (value != "mlx5ib" && value != "mlx4ib")
                fail("IB_DRIVER must be mlx5ib or mlx4ib")
        } else if (key == "PORT_GUID" && type[nic] == "infiniband") {
            value = tolower(value)
            if (length(value) != 23 || value !~ /^([0-9a-f][0-9a-f]:)*[0-9a-f][0-9a-f]$/ ||
                value == "00:00:00:00:00:00:00:00")
                fail("Invalid InfiniBand port GUID for " nic)
        } else if (key == "CONNECTED_MODE" && type[nic] == "infiniband") {
            if (value != "no")
                fail("The FreeBSD GENERIC IPoIB module supports datagram mode; use CONNECTED_MODE=no")
        } else if (key == "PKEY" && type[nic] == "vlan") {
            value = tolower(value)
            if (value !~ /^0x[89abcdef][0-9a-f][0-9a-f][0-9a-f]$/ ||
                !number(hex_number(substr(value, 3)) - 32768 "", 1, 4094))
                fail("FreeBSD IPoIB partitions require a full-member PKEY from 0x8001 to 0x8ffe")
        } else if (key == "BOOTPROTO") {
            if (value != "dhcp" && value != "static" && value != "none")
                fail("BOOTPROTO must be dhcp, static or none")
        } else if (key == "dhcp4" || key == "dhcp6") {
            if (value != "true" && value != "false")
                fail(key " must be true or false")
        } else if (key == "PEERDNS" || key == "DEFROUTE" || key == "DHCPV6C" || key == "IPV6_DEFROUTE") {
            if (value != "yes" && value != "no")
                fail(key " must be yes or no")
        } else if (key == "LAGGPROTO" && type[nic] == "lagg") {
            if (value != "failover" && value != "lacp")
                fail("LAGGPROTO must be failover or lacp")
        } else if (key == "VLAN_TAG" && type[nic] == "vlan") {
            if (!number(value, 1, 4094))
                fail("Invalid VLAN_TAG for " nic)
        } else if (key == "STP" && type[nic] == "bridge") {
            if (value != "yes" && value != "no")
                fail("STP must be yes or no")
        } else
            fail("Unsupported FreeBSD option " key " for " nic)
        option[nic, key] = value
    }
    if (option[nic, "BOOTPROTO"] != "" && option[nic, "dhcp4"] != "" &&
        (option[nic, "BOOTPROTO"] == "dhcp") != (option[nic, "dhcp4"] == "true"))
        fail("Conflicting DHCP options for " nic)
    dhcp[nic] = option[nic, "BOOTPROTO"] == "dhcp" || option[nic, "dhcp4"] == "true"
    if (option[nic, "DHCPV6C"] != "" && option[nic, "dhcp6"] != "" &&
        (option[nic, "DHCPV6C"] == "yes") != (option[nic, "dhcp6"] == "true"))
        fail("Conflicting DHCPv6 options for " nic)
    dhcp6[nic] = option[nic, "DHCPV6C"] == "yes" || option[nic, "dhcp6"] == "true"
    if ((!dhcp[nic] && option[nic, "DEFROUTE"] != "") ||
        (!dhcp6[nic] && option[nic, "IPV6_DEFROUTE"] != "") ||
        (!dhcp[nic] && !dhcp6[nic] && option[nic, "PEERDNS"] != ""))
        fail("PEERDNS and default route options require the corresponding DHCP family for " nic)
}

function visit(nic,    i, parent) {
    if (visited[nic] == 2)
        return
    if (visited[nic] == 1)
        fail("Cyclic interface dependency at " nic)
    visited[nic] = 1
    for (i = 1; i <= member_count[nic]; i++) {
        parent = member[nic, i]
        visit(parent)
    }
    ib[nic] = type[nic] == "infiniband" || (member_count[nic] && ib[member[nic, 1]])
    for (i = 1; i <= member_count[nic]; i++)
        if (ib[nic] != ib[member[nic, i]])
            fail("Ethernet and InfiniBand cannot share an aggregate: " nic)
    if (ib[nic]) {
        if (type[nic] == "bridge")
            fail("FreeBSD bridges require Ethernet members")
        if (type[nic] == "lagg" && option[nic, "LAGGPROTO"] != "failover")
            fail("InfiniBand LAGG supports failover only")
        if (type[nic] == "vlan" && type[member[nic, 1]] != "infiniband")
            fail("InfiniBand partitions require a physical ibN parent")
        if (option[nic, "MACADDR"] != "")
            fail("InfiniBand link addresses cannot be set with MACADDR")
    } else if (option[nic, "PKEY"] != "" || ib_bond[nic])
        fail("InfiniBand options require InfiniBand members: " nic)
    visited[nic] = 2
    order[++ordered] = nic
}

function topology(    nic, count, i, j, parts, parent, tag, name) {
    for (nic in interfaces) {
        names[++total] = nic
        type[nic] = tolower(attributes["NICTYPES", nic])
        if (type[nic] == "bond-infiniband") {
            ib_bond[nic] = 1
            type[nic] = "lagg"
        }
        if (type[nic] == "bond")
            type[nic] = "lagg"
        if (type[nic] !~ /^(ethernet|infiniband|lagg|vlan|bridge)$/)
            fail("Missing or unsupported nictypes for " nic)
        if (!physical(type[nic]) && nic !~ ("^" type[nic] "[0-9]+$"))
            fail("Use a native " type[nic] " interface name for " nic)
        if (type[nic] == "infiniband" && nic !~ /^ib[0-9]+$/)
            fail("Use a native ibN InfiniBand interface name for " nic)
        if (type[nic] == "ethernet" && nic ~ /^(ib|lagg|vlan|bridge)[0-9]+$/)
            fail("A native IB interface or clone cannot be declared as Ethernet: " nic)
        if (attributes["NICCUSTOMSCRIPTS", nic] != "")
            fail("Use a separate postscript instead of niccustomscripts on FreeBSD")
        options(nic)
    }
    if (total > 64)
        fail("Too many interfaces")
    for (i = 2; i <= total; i++) {
        name = names[i]
        for (j = i - 1; j > 0 && names[j] > name; j--)
            names[j + 1] = names[j]
        names[j + 1] = name
    }
    for (i = 1; i <= total; i++) {
        nic = names[i]
        count = attributes["NICDEVICES", nic] == "" ? 0 : split(attributes["NICDEVICES", nic], parts, /\|/)
        if ((physical(type[nic]) && count != 0) || (type[nic] == "vlan" && count != 1) ||
            (type[nic] == "lagg" && (count < 2 || count > 16)) || (type[nic] == "bridge" && (count < 1 || count > 16)))
            fail("Invalid nicdevices membership for " nic)
        for (j = 1; j <= count; j++) {
            parent = parts[j]
            if (!(parent in interfaces) || parent == nic || (nic SUBSEP parent) in edge)
                fail("Missing, duplicate or self-referencing member of " nic)
            if (parent == bootnic && configure_boot != 1)
                fail("Use confignetwork -s to include the installation interface")
            if (type[parent] == "bridge" || (type[nic] == "lagg" && !physical(type[parent])) ||
                (type[nic] == "vlan" && !physical(type[parent]) && type[parent] != "lagg"))
                fail("Unsupported interface composition for " nic)
            if (type[nic] != "vlan") {
                if (parent in owner)
                    fail("Interface belongs to multiple aggregates: " parent)
                owner[parent] = nic
            }
            edge[nic, parent] = 1
            member[nic, ++member_count[nic]] = parent
        }
        if (type[nic] == "lagg" && option[nic, "LAGGPROTO"] == "")
            fail("Set LAGGPROTO explicitly for " nic)
        if (type[nic] == "vlan") {
            tag = option[nic, "VLAN_TAG"]
            if (option[nic, "PKEY"] != "") {
                if (tag != "" && tag != hex_number(substr(option[nic, "PKEY"], 3)) - 32768)
                    fail("PKEY and VLAN_TAG differ for " nic)
                tag = hex_number(substr(option[nic, "PKEY"], 3)) - 32768
            }
            if (tag == "")
                tag = substr(nic, 5)
            if (!number(tag, 1, 4094))
                fail("Set VLAN_TAG for " nic)
            if ((parent SUBSEP tag) in vlan_tag)
                fail("Duplicate VLAN tag on " parent)
            vlan_tag[parent, tag] = 1
            option[nic, "VLAN_TAG"] = tag
        }
    }
    for (i = 1; i <= total; i++) {
        nic = names[i]
        if (nic == bootnic && configure_boot != 1)
            continue
        if (type[nic] == "vlan" && member[nic, 1] in owner)
            fail("A VLAN parent is an aggregate member: " member[nic, 1])
        visit(nic)
    }
}

function node_addresses(nic,    ips, nets, count, nc, i, name, ip, family, net, bits, mtu, gateway, key, parts, other, smaller) {
    count = attributes["NICIPS", nic] == "" ? 0 : split(attributes["NICIPS", nic], ips, /\|/)
    nc = attributes["NICNETWORKS", nic] == "" ? 0 : split(attributes["NICNETWORKS", nic], nets, /\|/)
    if (count > 32 || (count == 0 && nc != 0) || (count > 0 && nc != 1 && nc != count))
        fail("nicips and nicnetworks must describe the same addresses for " nic)
    if (count && nic in owner)
        fail("Put addresses on the aggregate instead of its member " nic)
    for (i = 1; i <= count; i++) {
        name = nets[nc == 1 ? 1 : i]
        if (network_count[name] != 1 || (network[name, "disable"] != "" && network[name, "disable"] !~ /^(0|no)$/))
            fail("Missing, duplicate or disabled network " name)
        family = index(ips[i], ":") ? "inet6" : "inet"
        ip = address(ips[i], family)
        if (family == "inet6" && ip ~ /^fe[89ab]/)
            fail("Link-local node addresses are assigned by FreeBSD")
        net = network[name, "net"]
        bits = prefix(network[name, "mask"], family)
        if (index(net, "/")) {
            if (split(net, parts, "/") != 2 || !number(parts[2], 0, 128) || parts[2] != bits)
                fail("Conflicting network prefix for " name)
            net = parts[1]
        }
        if ((family == "inet" && ipv4(net) == "") || (family == "inet6" && ipv6(net) == "") ||
            !subnet(ip, net, bits, family))
            fail("Address is outside network " name ": " ips[i])
        if (!network_address(net, bits, family))
            fail("Network contains host bits: " name)
        if (family == "inet" && bits < 31 &&
            (ipv4(ip) % 2 ^ (32 - bits) == 0 || ipv4(ip) % 2 ^ (32 - bits) == 2 ^ (32 - bits) - 1))
            fail("A node address cannot be a subnet or broadcast address")
        key = family SUBSEP ip
        if (key in assigned)
            fail("Duplicate node address " ips[i])
        assigned[key] = nic
        for (other = 1; other <= subnet_count; other++) {
            smaller = bits < subnet_bits[other] ? bits : subnet_bits[other]
            if (subnet_nic[other] != nic && subnet_family[other] == family &&
                subnet(ip, subnet_ip[other], smaller, family))
                fail("Overlapping subnets on different interfaces")
        }
        subnet_nic[++subnet_count] = nic
        subnet_family[subnet_count] = family
        subnet_ip[subnet_count] = ip
        subnet_bits[subnet_count] = bits
        if (ip == ENVIRON["IPADDR"]) {
            management = nic
            management_count++
        }
        address_family[nic, i] = family
        address_value[nic, i] = ip
        address_prefix[nic, i] = bits
        gateway = network[name, "gateway"]
        if (family == "inet" && ip != ENVIRON["IPADDR"])
            gateway = ""
        else if (gateway == "<xcatmaster>") {
            gateway = ""
            if (family == "inet" && !dhcp[nic] && !explicit_dhcp_default) {
                gateway = owned_ipv4_gateway
                if (gateway == "" && unmanaged_ipv4_gateway == "") {
                    gateway = leased_ipv4_gateway
                    if (gateway == "" && owned_dhcp_default != "" && leased_ipv4_default_absent != "yes")
                        fail("Cannot retain the DHCP default; set an explicit gateway before selecting static IPv4")
                }
            }
        }
        if (gateway != "") {
            if (index(gateway, "%")) {
                if (family != "inet6" || split(gateway, parts, "%") != 2 || parts[2] != nic)
                    fail("Gateway scope differs from interface")
                gateway = parts[1]
                if (ipv6(gateway) !~ /^fe[89ab]/)
                    fail("Only link-local gateways accept an interface scope")
            }
            gateway = address(gateway, family)
            if (family == "inet6" && gateway ~ /^fe[89ab]/)
                gateway = gateway "%" nic
            else if (!subnet(gateway, net, bits, family))
                fail("Gateway is outside network " name)
        }
        if (gateway == ip)
            fail("A node address cannot be its own gateway")
        if (gateway != "" && (family == "inet6" || ip == ENVIRON["IPADDR"])) {
            if (default_gateway[family] != "" && default_gateway[family] != gateway)
                fail("Ambiguous " family " default gateway")
            default_gateway[family] = gateway
        }
        mtu = network[name, "mtu"]
        if (mtu != "" && !number(mtu, 576, 9216))
            fail("Invalid network MTU for " name)
        if (ip == ENVIRON["IPADDR"])
            management_mtu = mtu
        if (option[nic, "MTU"] == "" && mtu != "") {
            if (network_mtu[nic] != "" && network_mtu[nic] != mtu)
                fail("Conflicting network MTUs for " nic)
            network_mtu[nic] = mtu + 0
        }
    }
    address_count[nic] = count
    if (dhcp[nic]) {
        for (i = 1; i <= count; i++)
            if (address_family[nic, i] == "inet") {
                dhcp_address[nic] = address_value[nic, i]
                dhcp_prefix[nic] = address_prefix[nic, i]
                dhcp_count[nic]++
            }
        if (dhcp_count[nic] != 1)
            fail("DHCP requires exactly one reserved IPv4 address in nicips for " nic)
        if (nic == management)
            delete default_gateway["inet"]
    }
    if (dhcp6[nic]) {
        for (i = 1; i <= count; i++)
            if (address_family[nic, i] == "inet6") {
                dhcp6_address[nic] = address_value[nic, i]
                dhcp6_count[nic]++
            }
        if (dhcp6_count[nic] != 1)
            fail("DHCPv6 requires exactly one reserved IPv6 address in nicips for " nic)
    }
}

function descends(nic, ancestor,    i) {
    if (nic == ancestor)
        return 1
    for (i = 1; i <= member_count[nic]; i++)
        if (descends(member[nic, i], ancestor))
            return 1
    return 0
}

function interface_mtu(nic,    mtu, i, parent_mtu) {
    mtu = option[nic, "MTU"] != "" ? option[nic, "MTU"] : network_mtu[nic]
    if (mtu == "") {
        mtu = member_count[nic] ? effective_mtu[member[nic, 1]] : (ib[nic] ? 2044 : 1500)
        for (i = 2; i <= member_count[nic]; i++)
            if (effective_mtu[member[nic, i]] < mtu)
                mtu = effective_mtu[member[nic, i]]
    }
    if (ib[nic] && mtu > 4092)
        fail("FreeBSD datagram IPoIB MTU cannot exceed 4092 on " nic)
    for (i = 1; i <= member_count[nic]; i++) {
        parent_mtu = effective_mtu[member[nic, i]]
        if (mtu > parent_mtu || ((type[nic] == "lagg" || type[nic] == "bridge") && mtu != parent_mtu))
            fail("Incompatible member MTU for " nic)
    }
    effective_mtu[nic] = mtu
}

function boot_defaults(target, mtu,    n, nic) {
    if (!mac_address(bootmac)) fail("Invalid installation MAC")
    if (mtu == "") mtu = 1500
    for (n = 1; n <= ordered; n++) {
        nic = order[n]
        if (!descends(target, nic)) continue
        if (type[nic] == "ethernet") {
            if (network_mtu[nic] == "") network_mtu[nic] = mtu
        } else if (descends(nic, bootnic) && option[nic, "MACADDR"] == "")
            option[nic, "MACADDR"] = bootmac
    }
}

function selected_routes(    names, count, i, name, values, net, bits, family, gateway, nic, j, reachable, parts, key, family_present) {
    if (ENVIRON["NODEROUTENAMES"] == "")
        return
    count = split(ENVIRON["NODEROUTENAMES"], names, ",")
    if (count > 64)
        fail("Too many selected routes")
    for (i = 1; i <= count; i++) {
        name = names[i]
        if (length(name) > 32 || name !~ /^[a-zA-Z][a-zA-Z0-9_]*$/ || name in route_seen)
            fail("Invalid or duplicate route name")
        route_seen[name] = 1
        if (split(ENVIRON["ROUTE_" name], values, ",") != 4)
            fail("Missing or invalid selected route " name)
        net = values[1]
        family = index(net, ":") ? "inet6" : "inet"
        bits = prefix(values[2], family)
        if (!bits)
            fail("Configure default gateways through networks.gateway")
        if (index(net, "/")) {
            if (split(net, parts, "/") != 2 || !number(parts[2], 1, 128) || parts[2] != bits)
                fail("Conflicting selected route prefix")
            net = parts[1]
        }
        if (family == "inet") {
            if (!network_address(net, bits, family))
                fail("Invalid selected route network")
        } else {
            net = ipv6(net)
            if (!network_address(net, bits, family) || net ~ /^ff/)
                fail("Invalid selected IPv6 route network")
        }
        nic = values[4]
        if (!visited[nic])
            fail("Selected routes require a configured ifname")
        gateway = values[3]
        if (index(gateway, "%")) {
            if (family != "inet6" || split(gateway, parts, "%") != 2 || parts[2] != nic)
                fail("Route gateway scope differs from ifname")
            gateway = parts[1]
            if (ipv6(gateway) !~ /^fe[89ab]/)
                fail("Only link-local gateways accept an interface scope")
        }
        gateway = address(gateway, family)
        reachable = 0
        family_present = 0
        for (j = 1; j <= address_count[nic]; j++) {
            if (address_family[nic, j] == family)
                family_present = 1
            if (address_family[nic, j] == family &&
                subnet(gateway, address_value[nic, j], address_prefix[nic, j], family))
                reachable = 1
        }
        if (family == "inet6" && gateway ~ /^fe[89ab]/ && family_present) {
            gateway = gateway "%" nic
            reachable = 1
        }
        if (!reachable)
            fail("Route gateway is not reachable through " nic)
        if ((family SUBSEP gateway) in assigned)
            fail("A node address cannot be its own route gateway")
        key = family SUBSEP net "/" bits
        if (key in route_destination)
            fail("Duplicate selected route destination")
        route_destination[key] = 1
        key = "xcat_net_" name
        if (family == "inet")
            routes4 = routes4 (routes4 == "" ? "" : " ") key
        else
            routes6 = routes6 (routes6 == "" ? "" : " ") key
        emit((family == "inet" ? "route_" : "ipv6_route_") key, "-net " net "/" bits " " gateway)
        records[++record_count] = "R\t" family "\t" net "/" bits "\t" gateway "\t" nic
    }
}

function emit(key, value) {
    if (key !~ /^[a-zA-Z][a-zA-Z0-9_]*$/ || value ~ /[^a-zA-Z0-9_ .:\/%-]/)
        fail("Unsafe generated network setting")
    records[++record_count] = "K\t" key "\t" value
}

function route_address(value, family,    parts, scope) {
    if (family == "inet")
        return value
    split(value, parts, "%")
    scope = parts[2] == "" ? "" : "%" parts[2]
    return ipv6(parts[1]) scope
}

function route_network(value, family,    parts, bits) {
    if (value == "default")
        return value
    split(value, parts, "/")
    bits = parts[2] == "" ? (family == "inet" ? 32 : 128) : parts[2]
    return route_address(parts[1], family) "/" bits
}

function render(nic,    i, config, mtu, parent, family, ip, bits, alias, first4, first6, primary4) {
    records[++record_count] = "I\t" nic "\t" type[nic]
    if (ib[nic])
        records[++record_count] = "G\t" nic "\t" option[nic, "PORT_GUID"]
    if (type[nic] == "infiniband") {
        records[++record_count] = "L\t" (option[nic, "IB_DRIVER"] == "" ? "mlx5ib" : option[nic, "IB_DRIVER"])
        records[++record_count] = "L\tipoib"
    }
    config = ""
    if (type[nic] == "lagg") {
        if (ib[nic]) {
            records[++record_count] = "J\t" nic "\tlaggtype infiniband"
            emit("create_args_" nic, "laggtype infiniband")
        }
        config = "laggproto " option[nic, "LAGGPROTO"]
        for (i = 1; i <= member_count[nic]; i++)
            config = config " laggport " member[nic, i]
    } else if (type[nic] == "vlan") {
        config = "vlan " option[nic, "VLAN_TAG"] " vlandev " member[nic, 1]
    } else if (type[nic] == "bridge") {
        for (i = 1; i <= member_count[nic]; i++) {
            parent = member[nic, i]
            config = config (config == "" ? "" : " ") "addm " parent
            if (option[nic, "STP"] != "no")
                config = config " stp " parent
        }
    }
    mtu = effective_mtu[nic]
    config = config (config == "" ? "" : " ") "mtu " mtu
    if (option[nic, "MACADDR"] != "") {
        records[++record_count] = "E\t" nic "\t" option[nic, "MACADDR"]
        config = "ether " option[nic, "MACADDR"] " " config
    }
    records[++record_count] = "X\t" nic "\t" config " up"
    records[++record_count] = "T\t" nic "\t" mtu
    for (i = 1; i <= address_count[nic]; i++)
        if (address_family[nic, i] == "inet6")
            ipv6_enabled[nic] = 1
    records[++record_count] = "V\t" nic "\t" (ipv6_enabled[nic] ? "-ifdisabled" : "ifdisabled")
    for (i = 1; i <= address_count[nic]; i++) {
        family = address_family[nic, i]
        ip = address_value[nic, i]
        bits = address_prefix[nic, i]
        if (family == "inet6" && mtu != "" && mtu < 1280)
            fail("IPv6 requires an MTU of at least 1280 on " nic)
        if (family == "inet" && !first4++) {
            if (!dhcp[nic] && option[nic, "MACADDR"] != "")
                emit("ifconfig_" nic "_alias" alias++, "inet " ip "/" bits)
            else
                primary4 = "inet " ip "/" bits " "
        }
        else if (family == "inet6" && dhcp6[nic]) {
            bits = 128
            emit("ifconfig_" nic "_ipv6", "inet6 -ifdisabled")
        } else if (family == "inet6" && !first6++)
            emit("ifconfig_" nic "_ipv6", "inet6 " ip " prefixlen " bits)
        else
            emit("ifconfig_" nic "_alias" alias++, family " " ip "/" bits)
        records[++record_count] = "A\t" nic "\t" family "\t" ip "\t" bits
    }
    if (dhcp[nic]) {
        primary4 = ib[nic] ? "" : "SYNCDHCP "
        records[++record_count] = "H\t" nic "\t" dhcp_address[nic] "\t" dhcp_prefix[nic] "\t" \
            (option[nic, "PEERDNS"] == "no" ? "no" : "yes") "\t" \
            (option[nic, "DEFROUTE"] == "" ? (nic == management ? "yes" : "no") : option[nic, "DEFROUTE"])
        if (ib[nic])
            ipoib_dhcp4_interfaces++
        else
            emit("dhclient_flags_" nic, "-c /var/db/xcat/network/dhcp/" nic ".conf")
        if (option[nic, "DEFROUTE"] == "yes" || (option[nic, "DEFROUTE"] == "" && nic == management)) {
            if (++dhcp_defaults > 1 || default_gateway["inet"] != "")
                fail("Select one IPv4 default route owner")
            emit("defaultrouter", "NO")
        }
    }
    if (dhcp6[nic]) {
        dhcp6_default = (option[nic, "IPV6_DEFROUTE"] == "yes" ||
            (option[nic, "IPV6_DEFROUTE"] == "" && nic == management && default_gateway["inet6"] == ""))
        records[++record_count] = "H6\t" nic "\t" dhcp6_address[nic] "\t128\t" \
            (option[nic, "PEERDNS"] == "no" ? "no" : "yes") "\t" (dhcp6_default ? "yes" : "no")
        dhcp6_interfaces++
        if (dhcp6_default) {
            if (++dhcp6_defaults > 1 || default_gateway["inet6"] != "")
                fail("Select one IPv6 default route owner")
            emit("ipv6_defaultrouter", "NO")
        }
    }
    emit("ifconfig_" nic, primary4 config " up")
    if (!ipv6_enabled[nic])
        emit("ifconfig_" nic "_ipv6", "inet6 ifdisabled")
    if (!physical(type[nic]))
        clones = clones (clones == "" ? "" : " ") nic
}

function read_policy() {
    attribute("NICTYPES")
    attribute("NICDEVICES")
    attribute("NICIPS")
    attribute("NICNETWORKS")
    attribute("NICEXTRAPARAMS")
    attribute("NICCUSTOMSCRIPTS")
    networks()
    topology()
}

function dhcp4_reservations(    n, nic) {
    read_policy()
    for (n = 1; n <= ordered; n++) node_addresses(order[n])
    for (n = 1; n <= ordered; n++) {
        nic = order[n]
        if (!ib[nic]) continue
        interface_mtu(nic)
        if (dhcp[nic])
            records[++record_count] = nic "\t" dhcp_address[nic]
    }
    for (n = 1; n <= record_count; n++) print records[n]
}

function compile(    n) {
    if (!interface_name(bootnic) || (configure_boot != 0 && configure_boot != 1))
        fail("Missing installation interface selection")
    read_policy()
    for (n = 1; n <= ordered; n++)
        if (dhcp[order[n]] && option[order[n], "DEFROUTE"] == "yes")
            explicit_dhcp_default++
    for (n = 1; n <= ordered; n++)
        node_addresses(order[n])
    if (configure_boot == 1 && visited[bootnic] &&
        (management_count != 1 || !descends(management, bootnic)))
        fail("The installation interface topology must retain the management IPv4 address")
    if (configure_boot != 1 && management_count)
        fail("Use confignetwork -s to configure the management address")
    if (configure_boot == 1 && bootmac != "" && management != "" && descends(management, bootnic))
        boot_defaults(management, management_mtu)
    for (n = 1; n <= ordered; n++) {
        if ((dhcp[order[n]] || dhcp6[order[n]]) && type[order[n]] == "bridge" && option[order[n], "MACADDR"] == "")
            fail("Set MACADDR for a bridge DHCP reservation")
        interface_mtu(order[n])
        render(order[n])
    }
    selected_routes()
    if (ipoib_dhcp4_interfaces) emit("xcat_ipoib_dhcp4_enable", "YES")
    if (dhcp6_interfaces) emit("xcat_dhcp6_enable", "YES")
    if (default_gateway["inet"] != "") {
        emit("defaultrouter", default_gateway["inet"])
        records[++record_count] = "D\tinet\t" default_gateway["inet"]
    }
    if (default_gateway["inet6"] != "") {
        emit("ipv6_defaultrouter", default_gateway["inet6"])
        records[++record_count] = "D\tinet6\t" default_gateway["inet6"]
    }
    print "F\txcat-freebsd-network-1"
    print "C\t" clones
    print "S\tinet\t" routes4
    print "S\tinet6\t" routes6
    for (n = 1; n <= record_count; n++)
        print records[n]
}

function bootstrap(    n, nic, mac, first, selected_clones) {
    configure_boot = 1
    if (bootstrap_mtu == "") bootstrap_mtu = 1500
    if (!number(bootstrap_mtu, 576, 9216)) fail("Invalid bootstrap network MTU")
    attribute("NICTYPES")
    attribute("NICDEVICES")
    attribute("NICEXTRAPARAMS")
    attribute("NICMACS")
    if (!interface_name(bootstrapnic) || !(bootstrapnic in interfaces) ||
        !mac_address(bootmac))
        fail("Invalid bootstrap interface or MAC")
    for (nic in interfaces)
        if (tolower(attributes["NICMACS", nic]) == bootmac && tolower(attributes["NICTYPES", nic]) == "ethernet") {
            if (bootnic != "") fail("Ambiguous bootstrap MAC")
            bootnic = nic
        }
    if (bootnic == "") fail("nicmacs must identify the physical boot interface")
    topology()
    if (!descends(bootstrapnic, bootnic)) fail("The bootstrap interface must contain the boot NIC")
    boot_defaults(bootstrapnic, bootstrap_mtu)
    for (n = 1; n <= ordered; n++) {
        nic = order[n]
        if (!descends(bootstrapnic, nic)) continue
        if (type[nic] == "ethernet") {
            mac = tolower(attributes["NICMACS", nic])
            if (!mac_address(mac) ||
                hex_number(substr(mac, 1, 2)) % 2 || mac == "00:00:00:00:00:00" || physical_mac[mac]++)
                fail("Each bootstrap physical NIC requires a distinct unicast nicmacs entry")
            records[++record_count] = "M\t" nic "\t" mac
        } else if (descends(nic, bootnic)) {
            if (option[nic, "MACADDR"] != "" && option[nic, "MACADDR"] != bootmac)
                fail("Bootstrap clones must retain the provisioning MAC")
            if (type[nic] == "lagg" && member[nic, 1] != bootnic)
                fail("The boot NIC must be the first LAGG port")
        }
        # The installer selects DHCP or static IPv4 separately. Installed-node
        # DHCP, IPv6 and route settings remain in the normal network planner.
        dhcp[nic] = dhcp6[nic] = 0
        interface_mtu(nic)
        render(nic)
    }
    print "F\txcat-freebsd-bootstrap-1"
    print "B\t" bootstrapnic
    print "C\t" clones
    for (n = 1; n <= record_count; n++) print records[n]
}

function static_options(value, ipv6_args,    count, words, i, item, parts, suffix) {
    count = split(value, words, /[ \t]+/)
    for (i = 1; i <= count; i++) {
        item = words[i]
        if (item == "" || item ~ /^(inet|inet6|up|down|alias|ifdisabled|-ifdisabled)$/)
            continue
        if ((!ipv6_args && item ~ /^(DHCP|SYNCDHCP)$/) ||
            (ipv6_args && toupper(item) ~ /^(DHCP|NOAUTO|NOSYNCDHCP|SYNCDHCP|WPA|HOSTAP)$/))
            continue
        if (item == "mtu" || item == "prefixlen") {
            if (!number(words[++i], 0, item == "mtu" ? 65535 : 128))
                return 0
        } else if (item == "netmask" || item == "broadcast") {
            item = words[++i]
            if (ipv4(item) == "" && item !~ /^0x[0-9a-fA-F]+$/)
                return 0
        } else {
            suffix = split(item, parts, "/")
            if (suffix > 2 || (suffix == 2 && !number(parts[2], 0, index(parts[1], ":") ? 128 : 32)))
                return 0
            if (ipv4(parts[1]) == "" && ipv6(parts[1]) == "")
                return 0
        }
    }
    return 1
}

# RFC 3442 suppresses the routers option even when it contains no default.
function lease_default(    count, bytes, i, width, size, gateway, routers) {
    if (lease["old_classless_routes"] != "") {
        count = split(lease["old_classless_routes"], bytes, " ")
        for (i = 1; i <= count; i++)
            if (!number(bytes[i], 0, 255)) fail("Invalid DHCP classless route byte")
        for (i = 1; i <= count; i += size + 5) {
            width = bytes[i]
            size = int((width + 7) / 8)
            if (width > 32 || i + size + 4 > count) fail("Incomplete DHCP classless route")
            if (width == 0 && gateway == "")
                gateway = bytes[i + 1] "." bytes[i + 2] "." bytes[i + 3] "." bytes[i + 4]
        }
    } else {
        split(lease["old_routers"], routers, " ")
        gateway = routers[1]
    }
    if (gateway == "") return
    if (ipv4(gateway) == "") fail("Invalid DHCP default gateway")
    if (gateway == "0.0.0.0" || gateway == lease["old_ip_address"])
        print "Q\tinet\t" nic
    else
        print "R\tinet\tdefault\t" gateway "\t" nic
}

BEGIN {
    if (mode == "dhcp4-routes") {
        if (lease_side !~ /^(old|new)$/) fail("Invalid DHCP lease side")
        route_text = ENVIRON[lease_side "_classless_static_routes"]
        if (route_text == "") route_text = ENVIRON[lease_side "_ms_classless_static_routes"]
        if (length(route_text) > 4096 || route_text ~ /[\r\n\t]/) fail("Invalid DHCP route option")
        route_count = split(route_text, route_words, " ")
        if (route_count % 2) fail("Incomplete DHCP route option")
        for (i = 1; i <= route_count; i += 2) {
            if (split(route_words[i], route_parts, "/") != 2 ||
                ipv4(route_parts[1]) == "" || !number(route_parts[2], 0, 32) ||
                !network_address(route_parts[1], route_parts[2], "inet") ||
                ipv4(route_words[i + 1]) == "") fail("Invalid DHCP route option")
            route_bytes = route_bytes (route_bytes == "" ? "" : " ") route_parts[2]
            split(route_parts[1], route_octets, ".")
            for (j = 1; j <= int((route_parts[2] + 7) / 8); j++)
                route_bytes = route_bytes " " route_octets[j]
            split(route_words[i + 1], route_octets, ".")
            for (j = 1; j <= 4; j++) route_bytes = route_bytes " " route_octets[j]
        }
        print route_bytes
        exit
    }
    if (mode == "bootstrap") {
        bootstrap()
        exit
    }
    if (mode == "dhcp4-reservations") {
        dhcp4_reservations()
        exit
    }
    if (mode == "dhcp6-duid" || mode == "dhcp4-duid") {
        uuid = tolower(uuid)
        if (uuid ~ /[^0-9a-f-]/ || split(uuid, uuid_parts, "-") != 5 ||
            length(uuid_parts[1]) != 8 || length(uuid_parts[2]) != 4 || length(uuid_parts[3]) != 4 ||
            length(uuid_parts[4]) != 4 || length(uuid_parts[5]) != 12 ||
            uuid == "00000000-0000-0000-0000-000000000000" || uuid == "ffffffff-ffff-ffff-ffff-ffffffffffff")
            fail("DHCP requires a valid hardware UUID")
        gsub(/-/, "", uuid)
        duid = "00:04"
        for (i = 1; i <= 32; i += 2) duid = duid ":" substr(uuid, i, 2)
        print duid
        exit
    }
    if (mode == "dhcp6-options") {
        lease_address = ""
        for (key in ENVIRON)
            if (key ~ /^new_dhcp6_ia_na[0-9]+_ia_addr[0-9]+$/) {
                lease_address = address(ENVIRON[key], "inet6")
                lease_addresses++
            }
        if (lease_addresses != 1 || lease_address != address(expected, "inet6"))
            fail("The DHCPv6 lease differs from the reserved address")
        if (peerdns == "yes") {
            count = split(ENVIRON["new_dhcp6_domain_search"], domains, " ")
            if (length(ENVIRON["new_dhcp6_domain_search"]) > 4096) fail("DHCPv6 search path exceeds its bound")
            for (i = 1; i <= count; i++) {
                if (domains[i] !~ /^[A-Za-z0-9_.-]+$/) fail("Invalid DHCPv6 search domain")
                search = search (i == 1 ? "" : " ") domains[i]
            }
            count = split(ENVIRON["new_dhcp6_name_servers"], servers, " ")
            if (count > 16) fail("Too many DHCPv6 name servers")
            for (i = 1; i <= count; i++) dns[i] = address(servers[i], "inet6")
            if (search != "") print "search " search
            for (i = 1; i <= count; i++) print "nameserver " dns[i] (dns[i] ~ /^fe[89ab]/ ? "%" ENVIRON["interface"] : "")
        }
        exit
    }
    if (mode == "" || mode == "compile") {
        compile()
        exit
    }
    if (mode != "links" && mode != "carrier" && mode != "dhcp4-default" && mode != "verify" && mode != "verify-prior" && mode != "snapshot" && mode != "clear" && mode != "routes" &&
        mode != "routeconflicts" && mode != "rcconflicts" && mode != "rcoptions" && mode != "rclists" && mode != "conflicts")
        fail("Unknown network planner operation")
}

mode == "dhcp4-default" {
    if (split($0, column, "\t") != 2 || column[1] in lease)
        fail("Invalid DHCP lease record")
    lease[column[1]] = column[2]
    next
}

FILENAME == ARGV[1] {
    fields = split($0, column, "\t")
    if (column[1] == "I")
        wanted_interface[column[2]] = column[3]
    else if (mode == "rclists" && (column[1] == "C" || column[1] == "S")) {
        key = column[1] == "C" ? "cloned_interfaces" : (column[2] == "inet" ? "static_routes" : "ipv6_static_routes")
        count = split(column[column[1] == "C" ? 2 : 3], words, " ")
        for (i = 1; i <= count; i++)
            owned_rc_list[key, words[i]] = 1
    }
    else if (column[1] == "K" && column[2] ~ /^(ipv6_)?route_xcat_net_/)
        wanted_rc_route[column[2]] = 1
    else if (column[1] == "A") {
        wanted_address[column[2], column[3], column[4]] = column[5]
        wanted_addressed[column[2]] = 1
    }
    else if (column[1] == "H")
        wanted_dhcp[column[2]] = 1
    else if (column[1] == "Q")
        wanted_dynamic_default[column[2]] = column[3]
    else if (column[1] == "H6") {
        wanted_dhcp6[column[2]] = 1
        if (column[6] == "yes") wanted_dynamic_default["inet6"] = column[2]
    }
    else if (column[1] == "T")
        wanted_mtu[column[2]] = column[3]
    else if (column[1] == "V")
        wanted_ipv6[column[2]] = column[3]
    else if (column[1] == "U")
        wanted_up[column[2]] = column[3]
    else if (column[1] == "E")
        wanted_ether[column[2]] = column[3]
    else if (column[1] == "G") {
        wanted_ib[column[2]] = 1
        wanted_guid[column[2]] = column[3]
    }
    else if (column[1] == "O")
        owned_route[column[2], route_network(column[3], column[2])] = 1
    else if (column[1] == "R") {
        key = column[2] SUBSEP route_network(column[3], column[2])
        wanted_gateway[key] = route_address(column[4], column[2])
        wanted_route_nic[key] = column[5]
    } else if (column[1] == "D")
        wanted_gateway[column[2], "default"] = route_address(column[3], column[2])
    else if (column[1] == "X") {
        count = split(column[3], words, " ")
        for (i = 1; i <= count; i++) {
            if (words[i] == "laggproto")
                wanted_protocol[column[2]] = words[i + 1]
            else if (words[i] == "laggport" || words[i] == "addm")
                wanted_member[column[2], words[i + 1]] = 1
            else if (words[i] == "stp")
                wanted_stp[column[2], words[i + 1]] = 1
            else if (words[i] == "vlan")
                wanted_vlan[column[2]] = words[i + 1]
            else if (words[i] == "vlandev")
                wanted_parent[column[2]] = words[i + 1]
        }
    }
    next
}

mode == "rcoptions" {
    position = index($0, ":")
    key = substr($0, 1, position - 1)
    value = substr($0, position + 1)
    for (nic in wanted_interface) {
        if (value ~ /[^ \t]/ && key ~ ("^ipv6_ifconfig_" nic "($|_alias[0-9]+$)"))
            fail("Interface options require manual integration: " key)
        if (!physical(wanted_interface[nic]))
            continue
        if (key ~ ("^ifconfig_" nic "($|_(ipv6|aliases|alias[0-9]+)$)") && !static_options(value, key ~ /_ipv6$/))
            fail("Interface options require manual integration: " key)
        if (value ~ /[^ \t]/ && (key == "ifconfig_" nic "_name" || key ~ ("^(create_args|vlans|ipv6_prefix)_" nic "$")))
            fail("Interface options require manual integration: " key)
    }
    next
}

mode == "rcconflicts" {
    position = index($0, ":")
    key = substr($0, 1, position - 1)
    if (key in wanted_rc_route)
        fail("A requested route has configuration outside the managed block")
    if (key == "static_routes" || key == "ipv6_static_routes" || key == "cloned_interfaces") {
        value = substr($0, position + 1)
        count = split(value, words, /[ \t]+/)
        for (i = 1; i <= count; i++) {
            if (key == "cloned_interfaces" && words[i] in wanted_interface && !physical(wanted_interface[words[i]]))
                fail("A requested clone has configuration outside the managed block")
            if (key != "cloned_interfaces" &&
                (((key == "static_routes" ? "route_" : "ipv6_route_") words[i]) in wanted_rc_route))
                fail("A requested route has configuration outside the managed block")
        }
    }
    for (nic in wanted_interface)
        if (!physical(wanted_interface[nic]) && key ~ ("^(ifconfig|create_args|vlans)_" nic "($|_)"))
            fail("A requested clone has configuration outside the managed block")
    next
}

mode == "rclists" {
    position = index($0, ":")
    key = substr($0, 1, position - 1)
    if (key == "cloned_interfaces" || key == "static_routes" || key == "ipv6_static_routes") {
        value = substr($0, position + 1)
        if (value ~ /[^A-Za-z0-9_ .:\t-]/)
            fail("Invalid names in " key)
        count = split(value, words, /[ \t]+/)
        for (i = 1; i <= count; i++)
            if (words[i] != "" && !((key SUBSEP words[i]) in owned_rc_list))
                retained_rc_list[key] = retained_rc_list[key] (retained_rc_list[key] == "" ? "" : " ") words[i]
    }
    next
}

mode == "routes" || mode == "routeconflicts" {
    if (expect_no_ipv4_default == "yes" && family == "inet" && $1 == "default")
        fail("An unexpected IPv4 default route is configured")
    if ($0 == "Internet:")
        family = "inet"
    else if ($0 == "Internet6:")
        family = "inet6"
    else if ($1 == "Destination") {
        for (i = 1; i <= NF; i++)
            if ($i == "Netif")
                route_nic_column = i
    } else if (family != "" && $3 ~ /[GS]/ && route_nic_column) {
        key = family SUBSEP route_network($1, family)
        observed_gateway[key] = route_address($2, family)
        observed_route_nic[key] = $route_nic_column
    }
    next
}

/^[^ \t:]+: flags=/ {
    current = $1
    sub(/:$/, "", current)
    if (!(current in wanted_interface) && mode != "conflicts")
        next
    observed_interface[current] = 1
    up[current] = $0 ~ /<UP[,>]/ ? "up" : "down"
    observed_carrier[current] = $0 ~ /[,<]LOWER_UP[,>]/ && $0 ~ /[,<]RUNNING[,>]/
    for (i = 1; i <= NF; i++)
        if ($i == "mtu")
            observed_mtu[current] = $(i + 1)
    next
}

current in wanted_interface || mode == "conflicts" {
    if ($1 == "inet" || $1 == "inet6") {
        family = $1
        ip = $2
        sub(/%.*/, "", ip)
        if (family == "inet6")
            ip = ipv6(ip)
        bits = -1
        for (i = 3; i <= NF; i++) {
            if ($i == "netmask") {
                mask = $(i + 1)
                if (mask ~ /^0x[0-9a-f]+$/) {
                    value = hex_number(substr(mask, 3))
                    bits = 32
                    remainder = 4294967295 - value
                    while (remainder > 0) {
                        if (remainder % 2 != 1)
                            fail("Invalid observed network mask")
                        remainder = int(remainder / 2)
                        bits--
                    }
                } else
                    bits = prefix(mask, "inet")
            } else if ($i == "prefixlen")
                bits = $(i + 1)
        }
        if (bits < 0 || ip == "")
            invalid_address[current] = 1
        else {
            observed_address[current, family, ip] = bits
            if (mode != "clear" && $0 ~ / (tentative|duplicated)( |$)/) {
                if (family == "inet6" && ip ~ /^fe[89ab]/)
                    invalid_link_local[current] = 1
                else
                    invalid_address[current] = 1
            }
        }
    } else if ($1 == "ether")
        ether[current] = $2
    else if ($1 == "lladdr")
        observed_ib[current] = ib_address($2)
    else if ($1 == "laggproto")
        observed_protocol[current] = $2
    else if ($1 == "laggport:" || $1 == "member:") {
        observed_member[current, $2] = 1
        observed_stp[current, $2] = $0 ~ /[,<]STP[,>]/
    } else if ($1 == "nd6") {
        observed_ipv6[current] = $0 ~ /[,<]IFDISABLED[,>]/ ? "ifdisabled" : "-ifdisabled"
        observed_rtadv[current] = $0 ~ /[,<]ACCEPT_RTADV[,>]/
    }
    else if ($1 == "vlan:") {
        observed_vlan[current] = $2
        for (i = 1; i < NF; i++)
            if ($i == "interface:")
                observed_parent[current] = $(i + 1)
    }
}

END {
    if (failed)
        exit 1
    if (mode == "dhcp4-default") {
        if (!interface_name(nic)) fail("Invalid DHCP interface")
        if (require_saved_lease == "yes" &&
            (ipv4(lease["old_ip_address"]) == "" || !("old_routers" in lease)))
            fail("Incomplete saved DHCP lease")
        lease_default()
    } else if (mode == "rclists") {
        print "cloned_interfaces: " retained_rc_list["cloned_interfaces"]
        print "static_routes: " retained_rc_list["static_routes"]
        print "ipv6_static_routes: " retained_rc_list["ipv6_static_routes"]
    } else if (mode == "conflicts") {
        for (nic in wanted_interface)
            if (observed_rtadv[nic])
                fail("Stop SLAAC configuration before managing " nic)
        for (key in observed_address) {
            split(key, parts, SUBSEP)
            if (configure_boot != 1 && parts[1] in wanted_interface &&
                parts[2] == "inet" && parts[3] == ENVIRON["IPADDR"])
                fail("Use confignetwork -s for the interface carrying the management address")
        }
        for (key in observed_member) {
            split(key, parts, SUBSEP)
            if (!(parts[1] in wanted_interface) && parts[2] in wanted_interface)
                fail("Interface belongs to unmanaged aggregate " parts[1])
        }
        for (nic in observed_parent)
            if (!(nic in wanted_interface) && observed_parent[nic] in wanted_interface)
                fail("Interface has unmanaged VLAN " nic)
        for (key in wanted_address) {
            split(key, parts, SUBSEP)
            for (other in observed_address) {
                split(other, existing, SUBSEP)
                if (existing[1] in wanted_interface || parts[2] != existing[2])
                    continue
                bits = wanted_address[key] < observed_address[other] ? wanted_address[key] : observed_address[other]
                if (subnet(parts[3], existing[3], bits, parts[2]))
                    fail("A configured subnet overlaps unmanaged interface " existing[1])
            }
        }
    } else if (mode == "routeconflicts") {
        for (key in observed_route_nic) {
            split(key, parts, SUBSEP)
            if (parts[2] != "default" && observed_route_nic[key] in wanted_interface &&
                !(parts[1] == "inet" ? wanted_dhcp[observed_route_nic[key]] : wanted_dhcp6[observed_route_nic[key]]) && !owned_route[key])
                fail("Unmanaged route uses a configured interface")
        }
    } else if (mode == "routes") {
        for (family in wanted_dynamic_default)
            if (observed_route_nic[family, "default"] != wanted_dynamic_default[family])
                fail("A DHCP default route is missing or uses another interface")
        for (key in wanted_gateway)
            if (observed_gateway[key] != wanted_gateway[key] ||
                (wanted_route_nic[key] != "" && observed_route_nic[key] != wanted_route_nic[key]))
                fail("A configured route or gateway is missing")
    } else if (mode == "links") {
        verify_links(0)
    } else if (mode == "carrier") {
        verify_existing_carrier()
    } else if (mode == "verify" || mode == "verify-prior") {
        for (nic in wanted_interface) {
            if (!observed_interface[nic] || up[nic] != (wanted_up[nic] == "" ? "up" : wanted_up[nic]) || invalid_address[nic] ||
                (invalid_link_local[nic] && observed_ipv6[nic] != "ifdisabled"))
                fail("Interface did not become ready: " nic)
        }
        verify_links(1)
        for (key in wanted_mtu)
            if (observed_mtu[key] != wanted_mtu[key])
                fail("Interface MTU differs: " key)
        for (key in wanted_address) {
            split(key, parts, SUBSEP)
            if (!(key in observed_address) && mode == "verify-prior" &&
                (parts[2] == "inet" ? wanted_dhcp[parts[1]] : wanted_dhcp6[parts[1]]))
                continue
            if (!(key in observed_address) || observed_address[key] != wanted_address[key])
                fail("A configured address or prefix is missing")
        }
        for (key in observed_address) {
            split(key, parts, SUBSEP)
            if (!(key in wanted_address) && !(parts[2] == "inet6" && parts[3] ~ /^fe[89ab]/))
                fail("An unexpected address is configured")
        }
        for (key in wanted_ipv6)
            if (observed_ipv6[key] != wanted_ipv6[key])
                fail("IPv6 interface state differs: " key)
        for (key in wanted_ether)
            if (ether[key] != wanted_ether[key])
                fail("Physical Ethernet address differs: " key)
        for (key in wanted_protocol)
            if (observed_protocol[key] != wanted_protocol[key])
                fail("LAGG protocol differs: " key)
        for (key in wanted_member)
            if (!observed_member[key])
                fail("An aggregate member is missing")
        for (key in observed_member) {
            split(key, parts, SUBSEP)
            if (!wanted_member[key] || (wanted_interface[parts[1]] == "bridge" && observed_stp[key] != (wanted_stp[key] + 0)))
                fail("Aggregate membership or STP differs")
        }
        for (key in wanted_vlan)
            if (observed_vlan[key] != wanted_vlan[key] || observed_parent[key] != wanted_parent[key])
                fail("VLAN parent or tag differs: " key)
    } else if (mode == "snapshot" || mode == "clear") {
        for (nic in observed_interface) {
            if (!physical(wanted_interface[nic]))
                continue
            if (wanted_interface[nic] == "ethernet")
                print "E\t" nic "\t" ether[nic]
            else {
                if (observed_ib[nic] == "")
                    fail("Cannot save an InfiniBand interface without its link address")
                print "G\t" nic "\t" substr(observed_ib[nic], 37)
            }
            print "T\t" nic "\t" observed_mtu[nic]
            if (invalid_address[nic] || (invalid_link_local[nic] && observed_ipv6[nic] != "ifdisabled"))
                fail("Cannot save an interface with tentative or duplicate addresses")
            for (key in observed_address) {
                split(key, parts, SUBSEP)
                if (parts[1] == nic && (mode == "clear" ||
                    !(parts[2] == "inet6" && parts[3] ~ /^fe[89ab]/ && observed_ipv6[nic] == "ifdisabled")))
                    print "A\t" nic "\t" parts[2] "\t" parts[3] "\t" observed_address[key]
            }
            print "V\t" nic "\t" observed_ipv6[nic]
            print "U\t" nic "\t" up[nic]
        }
    }
}
