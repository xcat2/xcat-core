"""Sending, receiving and running scenarios. The only module that uses scapy.

Everything is raw Layer 2: the tool builds the whole frame, so it works on an
interface that has no address yet, which is the normal state of a provisioning
NIC and the reason the existing Perl probe cannot be used there.
"""

import ipaddress
import os
import random
import select
import time

from . import assertions as assertions_mod
from . import machine, netutil, report, subst
from . import options as opt
from .errors import (ConfigError, EnvironmentError_, EXIT_OK)
from .subst import Context

BPF = "(udp and (port 67 or port 68)) or arp"


def _scapy():
    """Import scapy on demand, with a message a human can act on."""
    try:
        from scapy.all import (ARP, BOOTP, Ether, IP, UDP, Raw, conf, wrpcap)
    except ImportError:
        raise EnvironmentError_(
            "scapy is not installed; install the python3-scapy package")
    return dict(ARP=ARP, BOOTP=BOOTP, Ether=Ether, IP=IP, UDP=UDP, Raw=Raw,
                conf=conf, wrpcap=wrpcap)


class RunOptions(object):
    """Command-line overrides that apply to every scenario in a run."""

    def __init__(self, interface=None, mac=None, timeout=None, retries=None,
                 pcap=None, verbose=0):
        self.interface = interface
        self.mac = mac
        self.timeout = timeout
        self.retries = retries
        self.pcap = pcap
        self.verbose = verbose


class Session(object):
    """One client's state across the steps of a scenario."""

    def __init__(self, mac, interface):
        self.mac = mac
        self.mac_bytes = netutil.mac_bytes(mac)
        self.interface = interface
        self.state = machine.INIT
        self.xid = netutil.random_xid()
        self.context = Context()
        self.leases = set()          # addresses we may answer ARP for


# ---------------------------------------------------------------------------
# building packets


def _encode(code, text):
    """Turn a .conf value into the bytes of one DHCP option."""
    text = "" if text is None else str(text)
    if code in opt.IP_OPTIONS:
        return ipaddress.IPv4Address(text.strip()).packed
    if code in opt.IP_LIST_OPTIONS:
        blob = b""
        for item in text.split(","):
            blob += ipaddress.IPv4Address(item.strip()).packed
        return blob
    if code in opt.U32_OPTIONS:
        return int(text, 0).to_bytes(4, "big")
    if code in opt.U16_OPTIONS:
        return int(text, 0).to_bytes(2, "big")
    if code in opt.U8_OPTIONS:
        return int(text, 0).to_bytes(1, "big")
    if code == 55:
        return bytes(bytearray(opt.option_code(item.strip())
                               for item in text.split(",") if item.strip()))
    if code in opt.TEXT_OPTIONS:
        return text.encode("utf-8")
    return opt.parse_hex(text)


def build_options(step, session, context, msgtype):
    """The option area for one outgoing message."""
    def value(key, default=None):
        raw = step.param(key, default)
        return subst.resolve(raw, context) if raw is not None else None

    items = [(53, bytes([opt.msgtype_code(msgtype)]))]

    client_id = value("client_id", "auto")
    if client_id and client_id != "none":
        if client_id == "auto":
            items.append((61, b"\x01" + session.mac_bytes))
        else:
            items.append((61, _encode(61, client_id)))

    simple = [
        ("requested_address", 50), ("server_id", 54), ("lease_time", 51),
        ("hostname", 12), ("max_message_size", 57), ("vendor_class", 60),
        ("client_arch", 93), ("client_ndi", 94), ("client_uuid", 97),
        ("vendor_specific", 43), ("ipxe_options", 175),
        ("request_options", 55),
    ]
    for key, code in simple:
        text = value(key)
        if text not in (None, ""):
            items.append((code, _encode(code, text)))

    user_class = value("user_class")
    if user_class:
        form = (value("user_class_form") or "raw").lower()
        raw = user_class.encode("utf-8")
        if form == "rfc3004":
            raw = bytes([len(raw)]) + raw
        elif form != "raw":
            raise ConfigError("user_class_form must be 'raw' or 'rfc3004'")
        items.append((77, raw))

    for key, text in step.params.items():
        if key.startswith("option:"):
            code = opt.option_code(key)
            items.append((code, _encode(code, subst.resolve(text, context))))

    return items


def build_packet(step, session, context, msgtype, scapy):
    """One complete Ethernet frame carrying a DHCP message."""
    def value(key, default=None):
        raw = step.param(key, default)
        return subst.resolve(raw, context) if raw is not None else None

    ciaddr = value("ciaddr", "0.0.0.0")
    giaddr = value("giaddr", "0.0.0.0")
    transition = machine.transition_for(session.state, step.type)
    unicast = bool(transition and transition.unicast) and value("server_id")

    broadcast_flag = value("broadcast_flag")
    if broadcast_flag is None:
        flags = 0 if unicast or ciaddr != "0.0.0.0" else 0x8000
    else:
        flags = 0x8000 if broadcast_flag.strip().lower() in ("1", "yes", "true") else 0

    if unicast:
        dst_ip = value("server_id")
        dst_mac = value("dest_mac") or "ff:ff:ff:ff:ff:ff"
        src_ip = ciaddr
    else:
        dst_ip = "255.255.255.255"
        dst_mac = value("dest_mac") or "ff:ff:ff:ff:ff:ff"
        src_ip = ciaddr

    blob = opt.MAGIC + opt.pack_options(build_options(step, session, context, msgtype))
    min_size = int(value("min_size") or 300)
    if len(blob) < min_size - 240:
        blob += b"\x00" * (min_size - 240 - len(blob))

    frame = (
        scapy["Ether"](src=session.mac, dst=dst_mac) /
        scapy["IP"](src=src_ip, dst=dst_ip) /
        scapy["UDP"](sport=68, dport=67) /
        scapy["BOOTP"](op=1, htype=1, hlen=6, xid=session.xid, flags=flags,
                       ciaddr=ciaddr, giaddr=giaddr, chaddr=session.mac_bytes) /
        scapy["Raw"](load=blob)
    )
    return frame


def describe_sent(step, session, context, msgtype):
    """A one-line summary of what went out, for failure diagnostics."""
    parts = ["%s mac=%s xid=0x%08x" % (msgtype.upper(), session.mac, session.xid)]
    for key in sorted(step.params):
        if key in ("assert", "assert_all", "select", "collect_extra"):
            continue
        value = subst.resolve(step.params[key], context)
        if value not in (None, ""):
            parts.append("%s=%s" % (key, value))
    return " ".join(parts)


# ---------------------------------------------------------------------------
# the wire


class Wire(object):
    """A Layer 2 socket, opened before the first send so no reply is missed."""

    def __init__(self, interface, pcap=None, verbose=0):
        self.scapy = _scapy()
        if not netutil.interface_exists(interface):
            raise EnvironmentError_("no such interface: %s" % (interface,))
        if os.geteuid() != 0:
            raise EnvironmentError_("raw sockets need root; re-run with sudo")
        try:
            self.socket = self.scapy["conf"].L2socket(iface=interface, filter=BPF)
        except Exception as exc:                       # scapy raises many types
            raise EnvironmentError_(
                "cannot open a raw socket on %s: %s" % (interface, exc))
        self.pcap_path = pcap
        self.frames = []
        self.verbose = verbose

    def close(self):
        try:
            self.socket.close()
        finally:
            if self.pcap_path and self.frames:
                self.scapy["wrpcap"](self.pcap_path, self.frames)

    def send(self, frame):
        self.frames.append(frame)
        self.socket.send(frame)

    def collect(self, session, deadline, arp_for=()):
        """Every DHCP reply for this session until `deadline`.

        Frames that fail the cheap checks are dropped silently. A frame that
        is ours but carries an unexpected message type is still returned, so a
        NAK where an ACK was wanted is reported as a NAK rather than as a
        timeout.
        """
        found = []
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            ready, _, _ = select.select([self.socket], [], [], remaining)
            if not ready:
                break
            frame = self.socket.recv(2048)
            if frame is None:
                continue
            self.frames.append(frame)

            if arp_for and frame.haslayer("ARP"):
                self._answer_arp(frame, session, arp_for)
                continue

            if not frame.haslayer("BOOTP"):
                continue
            bootp = frame["BOOTP"]
            if int(bootp.op) != 2:
                continue
            if int(bootp.xid) != session.xid:
                continue
            if bytes(bootp.chaddr)[:6] != session.mac_bytes:
                continue
            if frame.haslayer("Ether") and frame["Ether"].src == session.mac:
                continue
            found.append(opt.decode(frame))
        return found

    def _answer_arp(self, frame, session, addresses):
        """Answer ARP only for addresses this session was actually granted.

        A server may ARP for the leased address before it unicasts a renewal
        reply. Answering here keeps the lease testable without ever putting the
        address on the host.
        """
        arp = frame["ARP"]
        if int(arp.op) != 1 or arp.pdst not in addresses:
            return
        reply = (
            self.scapy["Ether"](src=session.mac, dst=frame["Ether"].src) /
            self.scapy["ARP"](op=2, hwsrc=session.mac, psrc=arp.pdst,
                              hwdst=arp.hwsrc, pdst=arp.psrc)
        )
        self.send(reply)


# ---------------------------------------------------------------------------
# running


def run(scenarios, reporter, run_options):
    """Run every scenario and return a process exit code."""
    # A host with no scapy or no root cannot test anything. Reporting that as a
    # run of skipped tests would be a green result that proves nothing, so it
    # is raised before a single test point is emitted.
    _scapy()
    if os.geteuid() != 0:
        raise EnvironmentError_("raw sockets need root; re-run with sudo")

    reporter.start()
    for scenario in scenarios:
        interface = run_options.interface or scenario.interface
        if not interface:
            _skip(reporter, scenario, "no interface; pass -i")
            continue
        # An absent interface is a property of this host, not of the run: a
        # shared .conf may name a NIC that only some machines have.
        if not netutil.interface_exists(interface):
            _skip(reporter, scenario, "no such interface: %s" % (interface,))
            continue
        wire = Wire(interface, run_options.pcap, run_options.verbose)
        try:
            run_scenario(scenario, reporter, wire, run_options)
        finally:
            wire.close()
    reporter.finish()
    return reporter.exit_code()


def _skip(reporter, scenario, reason):
    for step in scenario.steps:
        for assertion in step.assertions:
            reporter.add(report.Record(
                scenario.name, step.name, assertion.render(), True,
                skip_reason=reason))


def run_scenario(scenario, reporter, wire, run_options):
    interface = run_options.interface or scenario.interface
    mac = run_options.mac
    if mac in (None, "", "random"):
        mac = netutil.random_mac()
    elif mac == "iface":
        mac = netutil.interface_mac(interface)
    else:
        mac = netutil.normalise_mac(mac)

    session = Session(mac, interface)

    for step in scenario.steps:
        run_step(scenario, step, session, reporter, wire, run_options)


def run_step(scenario, step, session, reporter, wire, run_options):
    context = session.context
    timeout = run_options.timeout or step.timeout
    retries = run_options.retries or step.retries

    if step.type == "sleep":
        time.sleep(float(subst.resolve(step.param("duration", "1"), context)))
        return

    if step.type == "noop":
        _record(reporter, scenario, step, step.assertions, None, context, "", 0, 0)
        return

    if step.param("mac"):
        session.mac = netutil.normalise_mac(subst.resolve(step.param("mac"), context))
        session.mac_bytes = netutil.mac_bytes(session.mac)

    transition = machine.transition_for(session.state, step.type)
    if transition is None:
        raise ConfigError("%s/%s: %r is not legal in state %s"
                          % (scenario.name, step.name, step.type, session.state))

    msgtype = _message_type(step.type)
    wanted = machine.expected_types(step, session.state)
    session.xid = netutil.random_xid()

    replies = []
    attempt = 0
    scapy = wire.scapy
    sent = ""
    for attempt in range(1, retries + 1):
        frame = build_packet(step, session, context, msgtype, scapy)
        sent = describe_sent(step, session, context, msgtype)
        if run_options.verbose:
            print("# send %s" % (sent,))
        wire.send(frame)
        deadline = time.monotonic() + timeout
        replies = wire.collect(session, deadline, arp_for=session.leases)
        if _pick(replies, wanted) is not None:
            break
        if not wanted and replies:
            break

    chosen = _pick(replies, wanted)
    if chosen is None and replies:
        chosen = replies[0]           # wrong type: report it, do not time out

    offers = _distinct(r for r in replies if r.msgtype == "OFFER")
    if chosen is not None and chosen.msgtype == "OFFER":
        chosen = _select_offer(offers, step, context) or chosen

    extras = {"offers": len(offers), "attempt": attempt}
    if chosen is not None:
        chosen.attempt = attempt
        context.bind(step.name, chosen)
        context.bind("reply", chosen)
        for name in transition.binds:
            if name == "offer" and chosen.msgtype != "OFFER":
                continue
            if name in ("ack", "lease") and chosen.msgtype != "ACK":
                continue
            context.bind(name, chosen)
        if chosen.msgtype == "ACK" and chosen.yiaddr != "0.0.0.0":
            session.leases.add(chosen.yiaddr)

    _record(reporter, scenario, step, step.assertions, chosen, context, sent,
            attempt, retries, extras)
    for offer in offers:
        _record(reporter, scenario, step, step.assertions_all, offer, context,
                sent, attempt, retries, extras, suffix=" [offer %s]" % offer.src_ip)

    expect = step.expect or transition.default_expect
    if expect == "none":
        return
    if chosen is None:
        return
    if chosen.msgtype == "NAK" and transition.nak_state:
        session.state = transition.nak_state
    elif transition.next_state:
        session.state = transition.next_state


def _distinct(replies):
    """One entry per answering server.

    Retransmits keep the same xid, as RFC 2131 requires, so an answer to an
    earlier attempt still matches a later one and the same server can be heard
    twice. `offers` is meant to count servers, not packets, so a second answer
    from a server already heard from is dropped.
    """
    seen = {}
    for reply in replies:
        key = reply.options.get(54) or reply.src_ip or reply.src_mac
        if key not in seen:
            seen[key] = reply
    return list(seen.values())


def _record(reporter, scenario, step, assertion_list, reply, context, sent,
            attempt, attempts, extras=None, suffix=""):
    for assertion in assertion_list:
        result = assertions_mod.evaluate(assertion, reply, context, extras)
        reporter.add(report.Record(
            scenario.name, step.name, assertion.render() + suffix,
            result.ok, expected=result.expected, actual=result.actual,
            detail=result.detail, reply=reply, sent=sent,
            attempt=attempt, attempts=attempts))


def _message_type(step_type):
    return {
        "discover": "discover", "request": "request", "renew": "request",
        "rebind": "request", "release": "release", "decline": "decline",
        "inform": "inform",
    }[step_type]


def _pick(replies, wanted):
    if not wanted:
        return None
    for reply in replies:
        if reply.msgtype.lower() in set(w.lower() for w in wanted):
            return reply
    return None


def _select_offer(offers, step, context):
    """Which OFFER drives the following REQUEST."""
    if not offers:
        return None
    rule = subst.resolve(step.param("select", "first"), context)
    if rule == "first":
        return offers[0]
    if rule == "with-bootfile":
        for offer in offers:
            if offer.file:
                return offer
        return offers[0]
    if rule.startswith("server-id:"):
        wanted = rule.split(":", 1)[1].strip()
        for offer in offers:
            if offer.options.get(54) == wanted:
                return offer
        return None
    raise ConfigError("unknown select=%r" % (rule,))


def ad_hoc_discover(interface, client_arch=None, vendor_class=None,
                    user_class=None, request_options=None):
    """A one-step scenario for `dhcptest discover`, built without a .conf."""
    from .model import Scenario, Step
    from . import assertions as assertions_mod

    params = {}
    if client_arch:
        params["client_arch"] = client_arch
    if vendor_class:
        params["vendor_class"] = vendor_class
    if user_class:
        params["user_class"] = user_class
    params["request_options"] = request_options or "1,3,6,15,28,51,54,66,67"

    step = Step(name="discover", type="discover", expect="offer", params=params,
                assertions=assertions_mod.parse_block(
                    "msgtype == OFFER\nyiaddr present", "<discover>"),
                source="<discover>")
    return Scenario(name="discover", description="ad-hoc DISCOVER",
                    interface=interface, steps=[step], source="<discover>")
