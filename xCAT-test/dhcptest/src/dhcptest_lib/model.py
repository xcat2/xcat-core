"""Plain data structures shared across the tool.

No network, no scapy, no I/O. Written for Python 3.6, so no dataclasses.
"""

from .errors import ConfigError


class Assertion(object):
    """One line of the assertion mini-language.

    `target op value`, for example::

        msgtype   == OFFER
        yiaddr    in 10.0.0.0/24
        option:54 present
        file      matches ^http://
    """

    __slots__ = ("target", "op", "value", "source", "text")

    def __init__(self, target, op, value, source="", text=""):
        self.target = target
        self.op = op
        self.value = value
        self.source = source
        self.text = text or self.render()

    def render(self):
        if self.value is None:
            return "%s %s" % (self.target, self.op)
        return "%s %s %s" % (self.target, self.op, self.value)

    def __repr__(self):
        return "Assertion(%r)" % (self.render(),)


class Step(object):
    """One protocol action plus the assertions made about its reply."""

    __slots__ = (
        "name",
        "type",
        "expect",
        "params",
        "assertions",
        "assertions_all",
        "timeout",
        "retries",
        "source",
    )

    def __init__(self, name, type, expect, params, assertions,
                 assertions_all=(), timeout=2.0, retries=3, source=""):
        self.name = name
        self.type = type
        self.expect = expect
        self.params = dict(params)
        self.assertions = tuple(assertions)
        self.assertions_all = tuple(assertions_all)
        self.timeout = timeout
        self.retries = retries
        self.source = source

    def param(self, key, default=None):
        return self.params.get(key, default)

    def __repr__(self):
        return "Step(%r, type=%r, expect=%r)" % (self.name, self.type, self.expect)


class Scenario(object):
    """A named sequence of steps run against one interface, in order."""

    __slots__ = ("name", "description", "interface", "steps", "source")

    def __init__(self, name, description="", interface=None, steps=(), source=""):
        self.name = name
        self.description = description
        self.interface = interface
        self.steps = tuple(steps)
        self.source = source

    def step(self, name):
        for step in self.steps:
            if step.name == name:
                return step
        raise ConfigError("no such step %r in scenario %r" % (name, self.name))

    def __repr__(self):
        return "Scenario(%r, steps=%d)" % (self.name, len(self.steps))


class Reply(object):
    """A decoded DHCP reply.

    Built by `options.decode()` from a scapy packet, but the class itself
    knows nothing about scapy, so assertions can be tested against synthetic
    replies with no capture and no root.
    """

    __slots__ = (
        "msgtype",
        "xid",
        "yiaddr",
        "siaddr",
        "ciaddr",
        "giaddr",
        "chaddr",
        "file",
        "sname",
        "secs",
        "flags",
        "options",
        "src_ip",
        "src_mac",
        "attempt",
        "raw",
    )

    def __init__(self, msgtype="", xid=0, yiaddr="0.0.0.0", siaddr="0.0.0.0",
                 ciaddr="0.0.0.0", giaddr="0.0.0.0", chaddr="", file="",
                 sname="", secs=0, flags=0, options=None, src_ip="",
                 src_mac="", attempt=0, raw=None):
        self.msgtype = msgtype
        self.xid = xid
        self.yiaddr = yiaddr
        self.siaddr = siaddr
        self.ciaddr = ciaddr
        self.giaddr = giaddr
        self.chaddr = chaddr
        self.file = file
        self.sname = sname
        self.secs = secs
        self.flags = flags
        self.options = dict(options or {})
        self.src_ip = src_ip
        self.src_mac = src_mac
        self.attempt = attempt
        self.raw = raw

    # -- the fields reachable through $step.<field> in a .conf ---------------

    #: Aliases so a .conf can say `$offer.address` rather than `$offer.yiaddr`.
    FIELD_ALIASES = {
        "address": "yiaddr",
        "mac": "chaddr",
        "next_server": "siaddr",
    }

    #: Fields a client derives from more than one place in the message.
    DERIVED_FIELDS = frozenset(["bootfile"])

    #: Fields that come from an option rather than the BOOTP header.
    FIELD_OPTIONS = {
        "server_id": 54,
        "lease_time": 51,
        "renewal_time": 58,
        "rebinding_time": 59,
        "subnet_mask": 1,
        "router": 3,
        "domain_name": 15,
        "hostname": 12,
        "vendor_class": 60,
        "user_class": 77,
    }

    def bootfile(self):
        """What this reply would actually make a client boot.

        RFC 2132 option 67 also carries a boot file name, and a server that was
        asked for option 67 may answer there and leave the BOOTP `file` header
        empty -- dnsmasq does exactly that, while ISC dhcpd fills the header.
        Firmware reads whichever arrived, so a test that looked only at the
        header would pass against one server and fail against another over a
        difference no client can observe.
        """
        return self.options.get(67) or self.file

    def field(self, name):
        """Resolve one `$step.<name>` reference, or raise KeyError."""
        if name == "bootfile":
            return self.bootfile()
        if name in self.FIELD_OPTIONS:
            code = self.FIELD_OPTIONS[name]
            if code not in self.options:
                raise KeyError(
                    "reply has no option %d, needed for .%s" % (code, name))
            return self.options[code]
        if name.startswith("opt"):
            try:
                code = int(name[3:], 0)
            except ValueError:
                raise KeyError("bad option reference .%s" % (name,))
            if code not in self.options:
                raise KeyError("reply has no option %d" % (code,))
            return self.options[code]
        target = self.FIELD_ALIASES.get(name, name)
        if target in self.__slots__ and target not in ("options", "raw"):
            return getattr(self, target)
        raise KeyError("unknown reply field .%s" % (name,))

    @classmethod
    def known_fields(cls):
        """Every `$step.<field>` name that can be validated offline."""
        names = set(cls.FIELD_OPTIONS)
        names.update(cls.FIELD_ALIASES)
        names.update(cls.DERIVED_FIELDS)
        names.update(
            f for f in cls.__slots__
            if f not in ("options", "raw", "attempt")
        )
        return names

    def summary(self):
        who = self.src_ip or "?"
        if self.src_mac:
            who = "%s (%s)" % (who, self.src_mac)
        return "%s from %s xid=0x%08x yiaddr=%s siaddr=%s file=%r" % (
            self.msgtype or "?", who, self.xid, self.yiaddr, self.siaddr,
            self.file)

    def __repr__(self):
        return "Reply(%s)" % (self.summary(),)
