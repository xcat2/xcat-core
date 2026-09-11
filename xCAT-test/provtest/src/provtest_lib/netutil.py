"""Address arithmetic, and nothing that touches a network.

Kept separate from the clients so that the assertion language can compare
addresses in a unit test with no interface, no root and no server.
"""

import ipaddress


def parse_ip(text):
    """An `IPv4Address`, or None when `text` is not one."""
    try:
        return ipaddress.IPv4Address(str(text).strip())
    except (ipaddress.AddressValueError, ValueError):
        return None


def ip_in(address, network):
    """True when `address` falls inside the CIDR block `network`."""
    ip = parse_ip(address)
    if ip is None:
        return False
    try:
        net = ipaddress.IPv4Network(str(network).strip(), strict=False)
    except (ipaddress.AddressValueError, ipaddress.NetmaskValueError, ValueError):
        return False
    return ip in net


def parse_range(text):
    """`first-last` as a pair of addresses, or None."""
    if text is None or "-" not in str(text):
        return None
    first, _, last = str(text).strip().partition("-")
    low, high = parse_ip(first), parse_ip(last)
    if low is None or high is None:
        return None
    return low, high


def ip_in_range(address, text):
    """True when `address` is inside an inclusive `first-last` range."""
    bounds = parse_range(text)
    ip = parse_ip(address)
    if bounds is None or ip is None:
        return False
    low, high = bounds
    return low <= ip <= high


def hex_ip(address, upper=True):
    """The eight-digit hex a PXE or grub2 loader asks for its address by.

    This is the encoding the loader itself performs, not xCAT's: 10.99.1.11
    becomes 0A63010B. It is here so a scenario can say what the name should be
    without the fixture having to compute it, and so the tool never has to ask
    xCAT what name it wrote.
    """
    ip = parse_ip(address)
    if ip is None:
        raise ValueError("not an IPv4 address: %r" % (address,))
    text = "%08X" % (int(ip),)
    return text if upper else text.lower()


def reverse_name(address):
    """The IN-ADDR.ARPA name a resolver is asked for a PTR by."""
    ip = parse_ip(address)
    if ip is None:
        raise ValueError("not an IPv4 address: %r" % (address,))
    return ip.reverse_pointer


def normalise_mac(text):
    """A MAC in the lowercase colon form, or ValueError."""
    raw = str(text).strip().lower().replace("-", ":").replace(".", ":")
    parts = [part for part in raw.split(":") if part != ""]
    if len(parts) != 6:
        raise ValueError("not a MAC address: %r" % (text,))
    octets = []
    for part in parts:
        if len(part) > 2:
            raise ValueError("not a MAC address: %r" % (text,))
        value = int(part, 16)
        octets.append("%02x" % (value,))
    return ":".join(octets)


def dashed_mac(text):
    """The `01-aa-bb-...` form a grub2 or pxelinux per-MAC file is named by."""
    return normalise_mac(text).replace(":", "-")
