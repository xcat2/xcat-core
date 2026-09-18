"""DHCP option names, numbers and value coding, and the decoded reply.

Scapy-free. The option area is read from raw bytes rather than through scapy's
option table, so a scapy release that renames an option cannot change what a
.conf asserts.
"""

import binascii
import ipaddress
import re

from .errors import ConfigError
from .model import Reply

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


#: Option 81's flag bits, in the order RFC 4702 numbers them. S says the server
#: is to update the A record, O that it overrode what the client asked for, E
#: that the name is in wire format rather than ASCII, and N that no update is
#: wanted at all.
FQDN_FLAGS = (("S", 0x01), ("O", 0x02), ("E", 0x04), ("N", 0x08))


def fqdn_flag_letters(flags):
    """`0x03` -> `"SO"`. An empty set of flags is `"-"`, so it prints."""
    return "".join(letter for letter, bit in FQDN_FLAGS if flags & bit) or "-"


def fqdn_flag_bits(letters):
    """`"SO"` -> `0x03`. Unknown letters are a config error, not a silent 0."""
    bits = 0
    known = dict(FQDN_FLAGS)
    for letter in str(letters).upper():
        if letter not in known:
            raise ConfigError(
                "unknown option 81 flag %r: expected any of S, O, E, N"
                % (letter,))
        bits |= known[letter]
    return bits


def encode_fqdn(text):
    """Encode a `fqdn` step value into option 81.

    `node01` sends the name with no flags; `S:node01` asks the server to do
    the update; `N:node01` asks for none. With E among the flags the name is
    sent in RFC 1035 wire format, which is what the option's E bit announces.
    """
    text = "" if text is None else str(text).strip()
    letters, _, name = text.partition(":")
    if not _ or not letters or not re.match(r"\A[SOENsoen]+\Z", letters):
        letters, name = "", text
    flags = fqdn_flag_bits(letters)
    if flags & 0x04:
        body = b""
        for label in name.rstrip(".").split("."):
            raw = label.encode("utf-8")
            if len(raw) > 63:
                raise ConfigError("DNS label longer than 63 bytes: %r" % (label,))
            body += bytes([len(raw)]) + raw
        body += b"\x00"
    else:
        body = name.encode("utf-8")
    return bytes([flags, 0, 0]) + body


def decode_fqdn(raw):
    """Option 81 as `(flags, name)`, or None when the bytes are not that.

    Returning None rather than guessing keeps a malformed option printable as
    hex instead of asserted against as a misreading.
    """
    data = bytes(raw)
    if len(data) < 3:
        return None
    flags = data[0]
    body = data[3:]
    if flags & 0x04:
        names = decode_name_list(body)
        if names is None:
            return None
        return flags, ".".join(names)
    return flags, body.decode("utf-8", "replace").rstrip("\x00")


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
        if code == 81:
            # The name alone, because that is the fact a scenario asserts: a
            # server must answer with the node's name and not the client's.
            # The flags are reached through the `fqdn_flags` target.
            decoded = decode_fqdn(raw)
            if decoded is not None:
                return decoded[1]
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


def encode_value(code, text):
    """The bytes of one option, from the text a .conf gives for it."""
    text = "" if text is None else str(text)
    if code in IP_OPTIONS:
        return ipaddress.IPv4Address(text.strip()).packed
    if code in IP_LIST_OPTIONS:
        return b"".join(ipaddress.IPv4Address(item.strip()).packed
                        for item in text.split(","))
    for width, codes in ((4, U32_OPTIONS), (2, U16_OPTIONS), (1, U8_OPTIONS)):
        if code in codes:
            return int(text, 0).to_bytes(width, "big")
    if code == 55:
        return bytes(option_code(item.strip())
                     for item in text.split(",") if item.strip())
    if code in TEXT_OPTIONS:
        return text.encode("utf-8")
    if code == 81:
        return encode_fqdn(text)
    return parse_hex(text)


#: BOOTP header fields, readable by name.
HEADER_FIELDS = ("msgtype", "xid", "yiaddr", "siaddr", "ciaddr", "giaddr",
                 "chaddr", "file", "sname", "secs", "flags", "src_ip", "src_mac")

#: Other names for header fields, so a .conf can say `$offer.address`.
ALIASES = {"address": "yiaddr", "mac": "chaddr", "next_server": "siaddr"}

#: Fields a client reads from more than one place in the message.
DERIVED_FIELDS = ("bootfile", "dns_name", "fqdn_flags")


def field_option(name):
    """The option code a field name stands for (`opt54`, `54`, `server_id`,
    `option:54`), or None."""
    if name.startswith("opt") and name[3:].isdigit():
        return int(name[3:])
    try:
        return option_code(name)
    except ConfigError:
        return None


def known_field(name):
    """True when a DHCP reply can carry a field called `name`."""
    name = ALIASES.get(name, name)
    return (name in DERIVED_FIELDS or name in HEADER_FIELDS
            or field_option(name) is not None)


class DhcpReply(Reply):
    """A decoded DHCP or BOOTP reply."""

    __slots__ = ("options", "raw_options")

    def __init__(self, fields, options=None, raw_options=b""):
        Reply.__init__(self, kind="dhcp", fields=fields)
        self.options = dict(options or {})
        # Option 81 is decoded to its name. Its flag bits are only in here.
        self.raw_options = raw_options

    def bootfile(self):
        """What a client boots: option 67 when sent, else the `file` header.

        ISC fills the header, dnsmasq answers in option 67, and firmware
        reads whichever arrived.
        """
        return self.options.get(67) or self.fields.get("file", "")

    def dns_name(self):
        """The node's name: option 81 when sent, else option 12.

        Kea answers a client that sent option 81 in option 81. ISC with
        `ignore client-updates` sends option 12 only.
        """
        return self.options.get(81) or self.options.get(12) or ""

    def fqdn_flags(self):
        """Option 81's flags as letters, `SO`; empty when there is no 81."""
        if 81 not in self.options:
            return ""
        decoded = decode_fqdn(unpack_options(self.raw_options).get(81, b""))
        return fqdn_flag_letters(decoded[0]) if decoded else ""

    def whole(self, name):
        name = ALIASES.get(name, name)
        if name in DERIVED_FIELDS:
            return getattr(self, name)()
        if name in self.fields:
            return self.fields[name]
        code = field_option(name)
        if code is None:
            raise KeyError("a DHCP reply has no field .%s" % (name,))
        if code not in self.options:
            raise KeyError("the reply has no option %d" % (code,))
        return self.options[code]

    field = whole

    def has(self, name):
        name = ALIASES.get(name, name)
        if name in DERIVED_FIELDS:
            return bool(self.whole(name))
        if name in self.fields:
            # A zeroed header field is the header saying nothing.
            return self.fields[name] not in ("", 0, "0.0.0.0")
        return field_option(name) in self.options

    def summary(self):
        f = self.fields
        who = f.get("src_ip") or "?"
        if f.get("src_mac"):
            who = "%s (%s)" % (who, f["src_mac"])
        return "%s from %s xid=0x%08x yiaddr=%s siaddr=%s file=%r" % (
            f.get("msgtype") or "?", who, f.get("xid", 0), f.get("yiaddr"),
            f.get("siaddr"), f.get("file", ""))

    def detail_lines(self):
        return [("options", "{" + ", ".join(
            "%s=%s" % (option_label(code), self.options[code])
            for code in sorted(self.options)) + "}")]


def decode(packet):
    """A `DhcpReply` from a scapy packet that carries a BOOTP layer."""
    bootp = packet["BOOTP"]
    blob = bytes(bootp.payload) if bootp.payload else b""
    if not blob:
        blob = bytes(getattr(bootp, "options", b"") or b"")
    options = dict((code, decode_value(code, raw))
                   for code, raw in unpack_options(blob).items())

    # A BOOTREPLY with no option 53 is the whole answer a BOOTP client gets.
    msgtype = msgtype_name(options[53]) if 53 in options else "BOOTREPLY"

    fields = {
        "msgtype": msgtype,
        "xid": int(getattr(bootp, "xid", 0)),
        "yiaddr": str(getattr(bootp, "yiaddr", "0.0.0.0")),
        "siaddr": str(getattr(bootp, "siaddr", "0.0.0.0")),
        "ciaddr": str(getattr(bootp, "ciaddr", "0.0.0.0")),
        "giaddr": str(getattr(bootp, "giaddr", "0.0.0.0")),
        "chaddr": format_hex(bytes(getattr(bootp, "chaddr", b""))[:6]),
        "file": _trim(getattr(bootp, "file", b"")),
        "sname": _trim(getattr(bootp, "sname", b"")),
        "secs": int(getattr(bootp, "secs", 0)),
        "flags": int(getattr(bootp, "flags", 0)),
        "src_ip": packet["IP"].src if packet.haslayer("IP") else "",
        "src_mac": packet["Ether"].src if packet.haslayer("Ether") else "",
    }
    return DhcpReply(fields, options, blob)


def _trim(value):
    """BOOTP `file` and `sname` are fixed-width and NUL padded."""
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    return value.split("\x00", 1)[0]
