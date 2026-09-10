"""Address and interface helpers built on the standard library only."""

import ipaddress
import os
import random
import re

from .errors import ConfigError, EnvironmentError_

MAC_RE = re.compile(r"^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$")

SYS_NET = "/sys/class/net"


def normalise_mac(text):
    """Accept `aa:bb:cc:dd:ee:ff`, `aa-bb-...` or `aabbccddeeff`."""
    cleaned = str(text).strip().lower().replace("-", ":")
    if ":" not in cleaned and len(cleaned) == 12:
        cleaned = ":".join(cleaned[i:i + 2] for i in range(0, 12, 2))
    if not MAC_RE.match(cleaned):
        raise ConfigError("not a MAC address: %r" % (text,))
    return cleaned


def random_mac(rng=None):
    """A locally administered unicast MAC.

    Using a synthetic address rather than the interface's own is what keeps
    the host's network stack out of the test: NetworkManager and any running
    dhclient never see the replies as theirs, and the kernel drops the unicast
    ones because neither the destination MAC nor the destination IP is local.
    """
    rng = rng or random
    octets = [0x02] + [rng.randint(0x00, 0xFF) for _ in range(5)]
    return ":".join("%02x" % o for o in octets)


def mac_bytes(mac):
    return bytes(bytearray(int(part, 16) for part in normalise_mac(mac).split(":")))


def interface_exists(name):
    return os.path.isdir(os.path.join(SYS_NET, name))


def interface_mac(name):
    """Read an interface's own MAC without shelling out to `ip`."""
    path = os.path.join(SYS_NET, name, "address")
    try:
        with open(path) as handle:
            return normalise_mac(handle.read().strip())
    except (IOError, OSError):
        raise EnvironmentError_("cannot read the MAC address of %r" % (name,))


def parse_ip(text):
    try:
        return ipaddress.IPv4Address(str(text).strip())
    except (ipaddress.AddressValueError, ValueError):
        return None


def parse_network(text):
    try:
        return ipaddress.IPv4Network(str(text).strip(), strict=False)
    except (ipaddress.AddressValueError, ipaddress.NetmaskValueError, ValueError):
        return None


def ip_in(address, network):
    """True when `address` sits inside CIDR `network`."""
    addr = parse_ip(address)
    net = parse_network(network)
    if addr is None or net is None:
        return False
    return addr in net


def random_xid(rng=None):
    rng = rng or random
    return rng.randint(1, 0xFFFFFFFF)
