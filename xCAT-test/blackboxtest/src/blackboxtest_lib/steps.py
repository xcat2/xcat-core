"""What each step type accepts, needs and returns.

Adding a protocol means adding a row here and a handler in `runner`. The
table is read offline by `config` and `validate`, so a misspelt key or reply
field fails before a packet is sent.
"""

from . import dhcp, dhcpopts

#: Keys every step accepts.
COMMON_KEYS = frozenset(["type", "expect", "timeout", "retries", "assert"])


class StepType(object):
    """One row of the table.

    `family` is `dhcp` for the raw-socket client, `service` for a request to
    a server, and `local` for a step that asks nothing of the network.
    """

    __slots__ = ("family", "keys", "required", "fields", "timeout", "retries",
                 "program")

    def __init__(self, family, keys=(), required=(), fields=(), timeout=5.0,
                 retries=2, program=None):
        self.family = family
        self.keys = COMMON_KEYS | frozenset(keys)
        self.required = tuple(required)
        self.fields = frozenset(fields)
        self.timeout = timeout
        self.retries = retries
        self.program = program

    def expectations(self):
        """The `expect=` values a step of this family can give."""
        if self.family == "dhcp":
            return frozenset(["offer", "ack", "nak", "bootreply", "any", "none"])
        return frozenset(["ok", "fail", "any"])


def _dhcp():
    # Retransmits come quicker than a service request's retries: a DHCP
    # server that is up answers in milliseconds.
    return StepType("dhcp", dhcp.STEP_KEYS, timeout=2.0, retries=3)


#: `bind` is the client's own address. xcatd names a client by the reverse
#: lookup of the address its connection came from, so the source address is
#: under test and is never left to the kernel's route selection.
TYPES = dict((name, _dhcp()) for name in dhcp.STEP_TYPES)
TYPES.update({
    "dns": StepType(
        "service", ["bind", "server", "port", "name", "rrtype", "recursion"],
        required=("server", "name"), program="dig",
        fields=["status", "flags", "count", "data", "type", "ttl", "name",
                "question", "answers", "authority", "server", "rcode"]),
    "tftp": StepType(
        "service", ["bind", "server", "port", "path", "mode"],
        required=("server", "path"), program="tftp",
        fields=["ok", "size", "sha256", "text", "error", "path", "server"]),
    "http": StepType(
        "service", ["bind", "server", "port", "path", "url", "method",
                    "header", "insecure"], program="curl",
        fields=["status", "size", "sha256", "text", "url", "header",
                "content_type", "error", "ok"]),
    "xcatreq": StepType(
        "service", ["bind", "server", "port", "command", "element", "raw",
                    "callback_port", "callback_listen", "callback_reply",
                    "callback_wait", "cert", "key", "source_port"],
        required=("server", "command"),
        # getcredentials nests its payload as <data><content/><desc/></data>.
        fields=["destiny", "kernel", "initrd", "kcmdline", "imgserver", "name",
                "error", "serverdone", "elements", "data", "text", "handshake",
                "ok", "callback_seen", "callback_data", "content", "desc"]),
    "monitor": StepType(
        "service", ["bind", "server", "port", "send", "source_port"],
        required=("server", "send"),
        fields=["greeting", "lines", "text", "ok", "closed", "error"]),
    "flowrequest": StepType(
        "service", ["bind", "server", "port", "message", "replies",
                    "source_port"],
        required=("server",), fields=["replies", "count", "ok", "error"]),
    "findme": StepType(
        "service", ["bind", "server", "port", "payload", "encoding",
                    "source_port", "callback_listen", "callback_wait"],
        required=("server",), fields=["callbacks", "count", "ok", "error"]),
    "extract": StepType(
        "local", ["from", "pattern", "group"], required=("from", "pattern"),
        fields=["value", "groups", "matched", "count"]),
    "noop": StepType("local"),
})

#: Reply fields read by key, as `header.content-type`.
MAPPING_FIELDS = frozenset(["header", "elements"])


def known_field(step_type, name):
    """True when a reply of `step_type` can carry a field called `name`.

    A list is indexed as `data.0`, a mapping read as `header.content-type`.
    """
    kind = TYPES[step_type]
    if kind.family == "dhcp":
        return dhcpopts.known_field(name)
    if name in kind.fields:
        return True
    head, _, tail = name.partition(".")
    if head not in kind.fields or not tail:
        return False
    return head in MAPPING_FIELDS or tail.lstrip("-").isdigit()
