"""The DHCP client: an RFC 2131 state machine on a raw Layer 2 socket.

A raw socket works on an interface that has no address, which is the normal
state of a provisioning NIC when a machine boots on it.

This is the only module that imports scapy, and only inside `Wire`, so the
transition table and `validate` need neither scapy nor root.
"""

import os
import select
import time

from . import dhcpopts, netutil, subst
from .errors import ConfigError, UnsupportedError

INIT = "INIT"
SELECTING = "SELECTING"
BOUND = "BOUND"

BPF = "(udp and (port 67 or port 68)) or arp"

#: Names a reply is bound under besides the step's own, with the message type
#: that earns each one. `reply` is whatever came back.
ALIASES = {"offer": "OFFER", "ack": "ACK", "lease": "ACK", "reply": None}


class Transition(object):
    """One legal `(state, step type)` pair."""

    __slots__ = ("message", "expects", "default_expect", "next_state",
                 "requires", "binds", "unicast")

    def __init__(self, message, expects, next_state, requires=(), binds=(),
                 unicast=False):
        self.message = message
        self.expects = frozenset(expects)
        self.default_expect = expects[0] if expects else "none"
        self.next_state = next_state
        self.requires = tuple(requires)
        self.binds = tuple(binds)
        self.unicast = unicast


TRANSITIONS = {
    (INIT, "discover"): Transition(
        "discover", ["offer"], SELECTING, binds=("offer",)),
    # BOOTP: a header with no option 53, and one reply is the whole exchange.
    (INIT, "bootrequest"): Transition(
        "bootrequest", ["bootreply"], INIT),
    (SELECTING, "request"): Transition(
        "request", ["ack", "nak"], BOUND, binds=("ack", "lease")),
    # INIT-REBOOT: a REQUEST with option 50 and no option 54.
    (INIT, "request"): Transition(
        "request", ["ack", "nak"], BOUND, requires=("requested_address",),
        binds=("ack", "lease")),
    (BOUND, "renew"): Transition(
        "request", ["ack", "nak"], BOUND, binds=("ack", "lease"), unicast=True),
    (BOUND, "rebind"): Transition(
        "request", ["ack", "nak"], BOUND, binds=("ack", "lease")),
    # Nothing answers a RELEASE. Giving the lease up is the whole step.
    (BOUND, "release"): Transition("release", [], INIT, unicast=True),
}

STEP_TYPES = frozenset(kind for _, kind in TRANSITIONS)

#: Step keys that become an option, in the order they are sent.
OPTION_KEYS = (
    ("requested_address", 50), ("server_id", 54), ("lease_time", 51),
    ("hostname", 12), ("fqdn", 81), ("max_message_size", 57),
    ("vendor_class", 60), ("client_arch", 93), ("client_ndi", 94),
    ("client_uuid", 97), ("vendor_specific", 43), ("ipxe_options", 175),
    ("request_options", 55),
)

#: Every key a DHCP step accepts, beyond the common ones.
STEP_KEYS = frozenset(key for key, _ in OPTION_KEYS) | frozenset([
    "mac", "ciaddr", "giaddr", "client_id", "user_class", "user_class_form"])


def transition(state, step_type):
    return TRANSITIONS.get((state, step_type))


def expected(step, trans):
    """The reply types a step waits for; empty when it waits for none."""
    expect = step.expect or trans.default_expect
    if expect == "none":
        return frozenset()
    if expect == "any":
        return trans.expects
    return frozenset([expect])


def advance(state, trans, answered, msgtype=None):
    """The client's state after a step.

    A step that waited for an answer and got none leaves the client where it
    was: an unanswered DISCOVER does not put it in SELECTING. Nothing answers
    a RELEASE, so it moves on regardless. `validate` walks the same rule.
    """
    if trans.expects and not answered:
        return state
    if msgtype == "NAK" and "nak" in trans.expects:
        return INIT
    return trans.next_state


# ---------------------------------------------------------------------------
# packets


class Session(object):
    """One client, across the DHCP steps of a scenario."""

    def __init__(self, wire):
        self.wire = wire
        self.mac = netutil.random_mac()
        self.state = INIT
        self.xid = 0
        self.leases = set()          # addresses to answer ARP for


def build_options(step, mac, msgtype, context):
    """`[(code, bytes)]` for one outgoing message."""
    def value(key, default=None):
        raw = step.param(key, default)
        return subst.resolve(raw, context) if raw is not None else None

    # A BOOTP client predates options 53 and 61, so it sends neither.
    bootp = msgtype == "bootrequest"
    items = [] if bootp else [(53, bytes([dhcpopts.msgtype_code(msgtype)]))]

    client_id = value("client_id", "none" if bootp else "auto")
    if client_id == "auto":
        items.append((61, b"\x01" + netutil.mac_bytes(mac)))
    elif client_id and client_id != "none":
        items.append((61, dhcpopts.parse_hex(client_id)))

    for key, code in OPTION_KEYS:
        text = value(key)
        if text not in (None, ""):
            items.append((code, dhcpopts.encode_value(code, text)))

    user_class = value("user_class")
    if user_class:
        raw = user_class.encode("utf-8")
        form = (value("user_class_form") or "raw").lower()
        if form == "rfc3004":
            raw = bytes([len(raw)]) + raw
        elif form != "raw":
            raise ConfigError("user_class_form must be 'raw' or 'rfc3004'")
        items.append((77, raw))
    return items


def build_frame(step, session, trans, context, scapy):
    """One Ethernet frame carrying the step's message."""
    def value(key, default):
        return subst.resolve(step.param(key, default), context)

    ciaddr = value("ciaddr", "0.0.0.0")
    server = value("server_id", "")
    unicast = trans.unicast and server
    # A client that cannot yet receive unicast asks for a broadcast reply.
    flags = 0 if unicast or ciaddr != "0.0.0.0" else 0x8000

    blob = dhcpopts.MAGIC + dhcpopts.pack_options(
        build_options(step, session.mac, trans.message, context))
    # RFC 1542: a BOOTP message is at least 300 bytes, 240 of them header.
    blob += b"\x00" * max(0, 60 - len(blob))

    return (scapy.Ether(src=session.mac, dst="ff:ff:ff:ff:ff:ff") /
            scapy.IP(src=ciaddr, dst=server if unicast else "255.255.255.255") /
            scapy.UDP(sport=68, dport=67) /
            scapy.BOOTP(op=1, htype=1, hlen=6, xid=session.xid, flags=flags,
                        ciaddr=ciaddr, giaddr=value("giaddr", "0.0.0.0"),
                        chaddr=netutil.mac_bytes(session.mac)) /
            scapy.Raw(load=blob))


def describe(step, session, trans, context):
    """A one-line summary of what went out, for a failure report."""
    parts = ["%s mac=%s xid=0x%08x" % (trans.message.upper(), session.mac,
                                       session.xid)]
    for key in sorted(step.params):
        value = subst.resolve(step.params[key], context)
        if value not in (None, ""):
            parts.append("%s=%s" % (key, value))
    return " ".join(parts)


# ---------------------------------------------------------------------------
# the wire


def scapy_module():
    """Import scapy on demand, with a message a human can act on."""
    try:
        import scapy.all
    except ImportError:
        raise UnsupportedError(
            "scapy is not installed; install the python3-scapy package")
    return scapy.all


def require():
    """Refuse, before any output, a host that cannot send a DHCP frame."""
    scapy_module()
    if os.geteuid() != 0:
        raise UnsupportedError("raw sockets need root; re-run with sudo")


class Wire(object):
    """A Layer 2 socket, opened before the first send so no reply is missed."""

    def __init__(self, interface):
        self.scapy = scapy_module()
        try:
            self.socket = self.scapy.conf.L2socket(iface=interface, filter=BPF)
        except Exception as exc:                  # scapy raises many types
            raise UnsupportedError(
                "cannot open a raw socket on %s: %s" % (interface, exc))

    def close(self):
        self.socket.close()

    def send(self, frame):
        self.socket.send(frame)

    def collect(self, session, deadline, stop=()):
        """Every reply to this session's xid until `deadline`, or until a
        reply of a type in `stop` arrives.

        A reply of an unexpected type is kept, so a NAK where an ACK was
        wanted is reported as a NAK rather than as a timeout.
        """
        found = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or any(r.fields["msgtype"] in stop for r in found) \
                    or not select.select([self.socket], [], [], remaining)[0]:
                return found
            frame = self.socket.recv(2048)
            if frame is None:
                continue
            if frame.haslayer("ARP"):
                self._answer_arp(frame, session)
                continue
            if not frame.haslayer("BOOTP"):
                continue
            bootp = frame["BOOTP"]
            if int(bootp.op) == 2 and int(bootp.xid) == session.xid \
                    and bytes(bootp.chaddr)[:6] == netutil.mac_bytes(session.mac) \
                    and frame["Ether"].src != session.mac:
                found.append(dhcpopts.decode(frame))

    def _answer_arp(self, frame, session):
        """Answer ARP for a leased address, so a unicast renewal reply arrives
        without the address ever being put on the host."""
        arp = frame["ARP"]
        if int(arp.op) != 1 or arp.pdst not in session.leases:
            return
        self.send(self.scapy.Ether(src=session.mac, dst=frame["Ether"].src) /
                  self.scapy.ARP(op=2, hwsrc=session.mac, psrc=arp.pdst,
                                 hwdst=arp.hwsrc, pdst=arp.psrc))


# ---------------------------------------------------------------------------
# running a step


def run_step(step, session, context, timeout, retries):
    """Send one message, retransmitting until a wanted reply arrives.

    Returns `(reply, extras, sent)`. `reply` is None when nothing answered.
    `$reply` and the aliases the transition earns are bound here; the runner
    binds the step's own name.
    """
    if step.param("mac"):
        session.mac = netutil.normalise_mac(
            subst.resolve(step.param("mac"), context))

    trans = transition(session.state, step.type)
    if trans is None:
        raise ConfigError("a %s step is not legal in state %s"
                          % (step.type, session.state))
    wanted = set(kind.upper() for kind in expected(step, trans))
    session.xid = netutil.random_xid()

    replies = []
    attempt = 0
    sent = ""
    for attempt in range(1, retries + 1):
        sent = describe(step, session, trans, context)
        session.wire.send(build_frame(step, session, trans, context,
                                      session.wire.scapy))
        replies = session.wire.collect(session, time.monotonic() + timeout,
                                       stop_on(step, wanted))
        if any(r.fields["msgtype"] in wanted for r in replies) \
                or (replies and not wanted):
            break

    chosen = next((r for r in replies if r.fields["msgtype"] in wanted),
                  replies[0] if replies else None)
    expect = step.expect or trans.default_expect
    got = chosen.fields["msgtype"] if chosen is not None else "no reply"
    extras = {
        "attempt": attempt,
        "offers": len(distinct_servers(
            r for r in replies if r.fields["msgtype"] == "OFFER")),
        # expect=none is met by silence; anything else by a wanted type.
        "expect": expect, "got": got,
        "met": chosen is None if not wanted else got in wanted,
    }

    msgtype = None
    if chosen is not None:
        chosen.sent = sent
        chosen.attempt = attempt
        msgtype = chosen.fields["msgtype"]
        context.bind("reply", chosen)
        for name in trans.binds:
            if ALIASES[name] == msgtype:
                context.bind(name, chosen)
        if msgtype == "ACK" and chosen.fields["yiaddr"] != "0.0.0.0":
            session.leases.add(chosen.fields["yiaddr"])

    session.state = advance(session.state, trans,
                            bool(wanted) and chosen is not None, msgtype)
    return chosen, extras, sent


def stop_on(step, wanted):
    """The reply types that end a step's listening window early.

    A step that counts `offers` must hear every server, so it listens for the
    whole timeout. So does `expect = none`, where silence is the result.
    """
    if any("offers" in (a.target, a.value)
           for a in step.assertions):
        return frozenset()
    return wanted


def distinct_servers(replies):
    """One reply per answering server.

    A retransmit reuses its xid, as RFC 2131 requires, so one server can be
    heard twice. `offers` counts servers, not packets.
    """
    seen = {}
    for reply in replies:
        key = reply.options.get(54) or reply.fields.get("src_ip")
        seen.setdefault(key, reply)
    return list(seen.values())
