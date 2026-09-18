"""Address arithmetic and interface lookups, standard library only."""

import ipaddress
import os
import random

from .errors import ConfigError

SYS_NET = "/sys/class/net"


def parse_ip(text):
    """An `IPv4Address`, or None when `text` is not one."""
    try:
        return ipaddress.IPv4Address(str(text).strip())
    except (ipaddress.AddressValueError, ValueError):
        return None


def ip_in(address, network):
    """True when `address` is inside the CIDR block `network`."""
    ip = parse_ip(address)
    try:
        net = ipaddress.IPv4Network(str(network).strip(), strict=False)
    except (ipaddress.AddressValueError, ipaddress.NetmaskValueError, ValueError):
        return False
    return ip is not None and ip in net


def parse_range(text):
    """`first-last` as a sorted pair of addresses, or None.

    A dynamic pool rarely lines up on a prefix boundary, so it is written as
    two addresses rather than as a CIDR block.
    """
    first, sep, last = str(text).strip().partition("-")
    low, high = parse_ip(first), parse_ip(last)
    if not sep or low is None or high is None:
        return None
    return (low, high) if low <= high else (high, low)


def ip_in_range(address, text):
    """True when `address` is inside the inclusive range `first-last`."""
    bounds = parse_range(text)
    ip = parse_ip(address)
    return bounds is not None and ip is not None and bounds[0] <= ip <= bounds[1]


def hex_ip(address):
    """The eight hex digits a PXE or grub2 loader asks for its address by.

    The loader does this encoding, not xCAT: 10.99.1.11 becomes 0A63010B.
    """
    ip = parse_ip(address)
    if ip is None:
        raise ValueError("not an IPv4 address: %r" % (address,))
    return "%08X" % (int(ip),)


def hex_net(address, prefix):
    """The name of a per-network configuration.

    A loader that finds no file for its own address asks for shorter
    prefixes of it. The per-network file carries as many hex digits as the
    netmask covers, rounded up: 10.99.1.0/24 is 0A6301.
    """
    try:
        bits = int(prefix)
    except (TypeError, ValueError):
        bits = -1
    if not 0 <= bits <= 32:
        raise ValueError("not a prefix length: %r" % (prefix,))
    return hex_ip(address)[:(bits + 3) // 4]


def reverse_name(address):
    """The in-addr.arpa name a PTR is asked for by."""
    ip = parse_ip(address)
    if ip is None:
        raise ValueError("not an IPv4 address: %r" % (address,))
    return ip.reverse_pointer


def normalise_mac(text):
    """`aa:bb:..`, `aa-bb-..` or `aabb..` in the lowercase colon form."""
    raw = str(text).strip().lower().replace("-", ":")
    if ":" not in raw and len(raw) == 12:
        raw = ":".join(raw[i:i + 2] for i in range(0, 12, 2))
    parts = raw.split(":")
    try:
        octets = [int(part, 16) for part in parts]
    except ValueError:
        octets = []
    if len(parts) != 6 or len(octets) != 6 \
            or any(len(p) > 2 or not p for p in parts):
        raise ConfigError("not a MAC address: %r" % (text,))
    return ":".join("%02x" % octet for octet in octets)


def dashed_mac(text):
    """The `aa-bb-..` form a grub2 or pxelinux per-MAC file is named by."""
    return normalise_mac(text).replace(":", "-")


def mac_bytes(mac):
    return bytes(int(part, 16) for part in normalise_mac(mac).split(":"))


def random_mac():
    """A locally administered unicast MAC.

    The host's own address would make NetworkManager and any dhclient read
    the replies as theirs. With a synthetic one, the kernel drops the unicast
    replies because neither the MAC nor the IP is local.
    """
    return ":".join("%02x" % o for o in [0x02] + [random.randint(0, 255)
                                                   for _ in range(5)])


def random_xid():
    return random.randint(1, 0xFFFFFFFF)


def interface_exists(name):
    return os.path.isdir(os.path.join(SYS_NET, name))
