"""DHCP option names, numbers and value coding.

This module is scapy-free on purpose. It owns the mapping between the names a
.conf file may use and the option codes that go on the wire, so that a scapy
version which renames one of its own option strings changes this table and
nothing else.
"""

import binascii
import ipaddress

from .errors import ConfigError

#: DHCP message types (option 53), by name.
MSGTYPE_BY_NAME = {
    "discover": 1,
    "offer": 2,
    "request": 3,
    "decline": 4,
    "ack": 5,
    "nak": 6,
    "release": 7,
    "inform": 8,
    "force_renew": 9,
}

MSGTYPE_BY_CODE = dict((v, k) for k, v in MSGTYPE_BY_NAME.items())

#: Canonical option names. Only options this tool can send, assert on, or
#: usefully print need an entry; anything else is addressed by number.
NAME_TO_CODE = {
    "subnet_mask": 1,
    "time_offset": 2,
    "router": 3,
    "time_server": 4,
    "name_server": 5,
    "domain_name_server": 6,
    "log_server": 7,
    "hostname": 12,
    "boot_file_size": 13,
    "domain_name": 15,
    "root_path": 17,
    "interface_mtu": 26,
    "broadcast_address": 28,
    "static_routes": 33,
    "ntp_server": 42,
    "vendor_specific": 43,
    "netbios_name_server": 44,
    "requested_address": 50,
    "lease_time": 51,
    "overload": 52,
    "message_type": 53,
    "server_id": 54,
    "parameter_request_list": 55,
    "error_message": 56,
    "max_message_size": 57,
    "renewal_time": 58,
    "rebinding_time": 59,
    "vendor_class": 60,
    "client_id": 61,
    "tftp_server_name": 66,
    "bootfile_name": 67,
    "user_class": 77,
    "client_fqdn": 81,
    "relay_agent_information": 82,
    "client_architecture": 93,
    "client_ndi": 94,
    "client_uuid": 97,
    "tcode": 101,
    "www_server": 114,
    "domain_search": 119,
    "classless_static_routes": 121,
    "ipxe_encap": 175,
    "conf_file": 209,
    "cumulus_provision_url": 239,
}

CODE_TO_NAME = dict((v, k) for k, v in NAME_TO_CODE.items())

#: Options whose value is one IPv4 address.
IP_OPTIONS = frozenset([1, 28, 32, 50, 54])
#: Options whose value is a list of IPv4 addresses.
IP_LIST_OPTIONS = frozenset([3, 4, 5, 6, 7, 42, 44, 41, 45, 65, 68, 69, 70])
#: Options whose value is an unsigned 32-bit integer.
U32_OPTIONS = frozenset([2, 51, 58, 59])
#: Options whose value is an unsigned 16-bit integer.
U16_OPTIONS = frozenset([13, 22, 26, 57, 93])
#: Options whose value is a single unsigned byte.
U8_OPTIONS = frozenset([19, 20, 23, 27, 29, 30, 31, 34, 36, 37, 39, 52, 53, 116])
#: Options whose value is text.
TEXT_OPTIONS = frozenset([12, 14, 15, 17, 18, 40, 56, 60, 62, 64, 66, 67, 77,
                          86, 87, 100, 101, 114, 209, 239])


def option_code(spec):
    """Resolve `54`, `"54"`, `"0x36"`, `"server_id"` or `"option:54"` to 54."""
    if isinstance(spec, int):
        return spec
    text = str(spec).strip()
    if text.lower().startswith("option:"):
        text = text.split(":", 1)[1].strip()
    if text in NAME_TO_CODE:
        return NAME_TO_CODE[text]
    normalised = text.replace("-", "_").lower()
    if normalised in NAME_TO_CODE:
        return NAME_TO_CODE[normalised]
    try:
        code = int(text, 0)
    except ValueError:
        raise ConfigError("unknown DHCP option %r" % (spec,))
    if not 0 <= code <= 255:
        raise ConfigError("DHCP option out of range: %r" % (spec,))
    return code


def option_label(code):
    """Human label for an option code: `54 (server_id)`."""
    name = CODE_TO_NAME.get(code)
    return "%d (%s)" % (code, name) if name else str(code)


def msgtype_name(code):
    """Map option 53's value to an upper-case name, or `TYPE-<n>`."""
    if isinstance(code, str):
        lowered = code.lower()
        if lowered in MSGTYPE_BY_NAME:
            return lowered.upper()
        return code.upper()
    name = MSGTYPE_BY_CODE.get(code)
    return name.upper() if name else "TYPE-%s" % (code,)


def msgtype_code(name):
    """Map `offer`, `OFFER` or `2` to 2."""
    if isinstance(name, int):
        return name
    text = str(name).strip().lower().replace("-", "_")
    if text in MSGTYPE_BY_NAME:
        return MSGTYPE_BY_NAME[text]
    try:
        return int(text, 0)
    except ValueError:
        raise ConfigError("unknown DHCP message type %r" % (name,))


def parse_hex(text):
    """Parse `0a:0b:0c`, `0a0b0c` or `0x0a0b0c` into bytes."""
    cleaned = str(text).strip().replace(":", "").replace(" ", "")
    if cleaned.lower().startswith("0x"):
        cleaned = cleaned[2:]
    if len(cleaned) % 2:
        raise ConfigError("hex value has an odd number of digits: %r" % (text,))
    try:
        return binascii.unhexlify(cleaned)
    except (binascii.Error, ValueError):
        raise ConfigError("not a hex value: %r" % (text,))


def format_hex(data):
    """Render bytes as `0a:0b:0c`, the form assertions compare against."""
    if isinstance(data, str):
        data = data.encode("latin-1")
    return ":".join("%02x" % b for b in bytearray(data))


#: Options carrying a list of DNS names in RFC 1035 wire form, which RFC 3397
#: allows to be compressed against earlier names in the same option.
NAME_LIST_OPTIONS = frozenset([119])


def decode_name_list(raw):
    """Decode RFC 3397 name lists into `["foo.com", "bar.com"]`.

    Returns None if the bytes are not a well-formed name list, so the caller
    can fall back to hex rather than assert against a misreading.
    """
    data = bytearray(raw)
    names = []
    pos = 0
    while pos < len(data):
        labels = []
        cursor = pos
        jumped = False
        seen = set()
        while True:
            if cursor >= len(data):
                return None
            length = data[cursor]
            if length == 0:
                cursor += 1
                break
            if length & 0xC0 == 0xC0:
                # A pointer back to a name already in this option. Follow it,
                # but never twice to the same offset: a self-referential
                # pointer would otherwise loop forever.
                if cursor + 1 >= len(data):
                    return None
                target = ((length & 0x3F) << 8) | data[cursor + 1]
                if target in seen or target >= len(data):
                    return None
                seen.add(target)
                if not jumped:
                    pos = cursor + 2
                    jumped = True
                cursor = target
                continue
            if length & 0xC0:
                return None
            start = cursor + 1
            end = start + length
            if end > len(data):
                return None
            labels.append(data[start:end].decode("utf-8", "replace"))
            cursor = end
        if not jumped:
            pos = cursor
        if labels:
            names.append(".".join(labels))
    return names or None


def decode_value(code, raw):
    """Normalise one option value into something an assertion can compare.

    Integers stay integers, addresses and text become strings, and anything
    else becomes a colon-separated hex string so it is at least printable and
    comparable.
    """
    if isinstance(raw, (list, tuple)):
        return [decode_value(code, item) for item in raw]
    if isinstance(raw, int):
        return raw
    if isinstance(raw, bytes):
        if code in TEXT_OPTIONS:
            return raw.decode("utf-8", "replace").rstrip("\x00")
        if code in IP_OPTIONS and len(raw) == 4:
            return str(ipaddress.IPv4Address(raw))
        if code in IP_LIST_OPTIONS and len(raw) % 4 == 0 and raw:
            return [str(ipaddress.IPv4Address(raw[i:i + 4]))
                    for i in range(0, len(raw), 4)]
        if code in U32_OPTIONS and len(raw) == 4:
            return int.from_bytes(raw, "big")
        if code in U16_OPTIONS and len(raw) == 2:
            return int.from_bytes(raw, "big")
        if code in U8_OPTIONS and len(raw) == 1:
            return raw[0]
        if code == 55:
            return list(bytearray(raw))
        if code in NAME_LIST_OPTIONS:
            names = decode_name_list(raw)
            if names is not None:
                return names
        return format_hex(raw)
    return raw


#: The DHCP magic cookie that introduces the option area (RFC 2132).
MAGIC = b"\x63\x82\x53\x63"


def pack_options(items):
    """Serialise `[(code, bytes), ...]` into an option area, END included."""
    blob = bytearray()
    for code, value in items:
        if code in (0, 255):
            continue
        if len(value) > 255:
            raise ConfigError("option %d is %d bytes, the limit is 255"
                              % (code, len(value)))
        blob.append(code)
        blob.append(len(value))
        blob.extend(value)
    blob.append(255)
    return bytes(blob)


def unpack_options(blob):
    """Parse an option area into `{code: raw bytes}`.

    Tolerates the magic cookie at the front, repeated options (concatenated
    per RFC 3396), padding and a missing END.
    """
    if blob.startswith(MAGIC):
        blob = blob[len(MAGIC):]
    found = {}
    index = 0
    while index < len(blob):
        code = blob[index]
        if code == 0:                      # PAD
            index += 1
            continue
        if code == 255:                    # END
            break
        if index + 1 >= len(blob):
            break
        length = blob[index + 1]
        value = blob[index + 2:index + 2 + length]
        found[code] = found.get(code, b"") + value
        index += 2 + length
    return found


def decode(packet):
    """Build a `model.Reply` from a scapy packet.

    The option area is parsed from raw bytes rather than through scapy's own
    option table, so a scapy release that renames one of its option strings
    cannot change what a .conf file asserts.
    """
    from .model import Reply          # local import: avoids a cycle

    bootp = packet["BOOTP"]
    blob = bytes(bootp.payload) if bootp.payload else b""
    if not blob:
        blob = bytes(getattr(bootp, "options", b"") or b"")
    options = {}
    for code, raw in unpack_options(blob).items():
        options[code] = decode_value(code, raw)

    # A BOOTREPLY with no option 53 is a plain BOOTP answer -- the whole reply
    # a client that predates DHCP will ever get. Naming it rather than leaving
    # the type blank is what lets a step assert on it.
    msgtype = "BOOTREPLY"
    if 53 in options:
        msgtype = msgtype_name(options[53])

    src_ip = ""
    src_mac = ""
    if hasattr(packet, "haslayer") and packet.haslayer("IP"):
        src_ip = packet["IP"].src
    if hasattr(packet, "haslayer") and packet.haslayer("Ether"):
        src_mac = packet["Ether"].src

    return Reply(
        msgtype=msgtype,
        xid=int(getattr(bootp, "xid", 0)),
        yiaddr=str(getattr(bootp, "yiaddr", "0.0.0.0")),
        siaddr=str(getattr(bootp, "siaddr", "0.0.0.0")),
        ciaddr=str(getattr(bootp, "ciaddr", "0.0.0.0")),
        giaddr=str(getattr(bootp, "giaddr", "0.0.0.0")),
        chaddr=format_hex(bytes(getattr(bootp, "chaddr", b""))[:6]),
        file=_trim(getattr(bootp, "file", b"")),
        sname=_trim(getattr(bootp, "sname", b"")),
        secs=int(getattr(bootp, "secs", 0)),
        flags=int(getattr(bootp, "flags", 0)),
        options=options,
        src_ip=src_ip,
        src_mac=src_mac,
        raw=packet,
    )


def _trim(value):
    """BOOTP `file` and `sname` are fixed-width and NUL padded."""
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    return value.split("\x00", 1)[0]
