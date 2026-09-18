"""The DHCP client: option coding, decoding, frames and the step loop."""

import unittest

import context

from blackboxtest_lib import config, dhcp, dhcpopts as opt, subst
from blackboxtest_lib.errors import ConfigError

try:
    import scapy.all as scapy
except ImportError:                                # pragma: no cover
    scapy = None


class Options(unittest.TestCase):

    def test_names_numbers_and_prefixes(self):
        for spec in (54, "54", "0x36", "server_id", "server-id",
                     "option:server_id"):
            self.assertEqual(opt.option_code(spec), 54, spec)
        self.assertRaises(ConfigError, opt.option_code, "not_an_option")
        self.assertRaises(ConfigError, opt.option_code, "256")

    def test_message_types(self):
        self.assertEqual(opt.msgtype_code("offer"), 2)
        self.assertEqual(opt.msgtype_name(2), "OFFER")
        self.assertEqual(opt.msgtype_name(99), "TYPE-99")

    def test_value_encoding_by_option(self):
        self.assertEqual(opt.encode_value(54, "10.0.0.1"), b"\x0a\x00\x00\x01")
        self.assertEqual(opt.encode_value(93, "0x000b"), b"\x00\x0b")
        self.assertEqual(opt.encode_value(55, "1, 3, server_id"), b"\x01\x03\x36")
        self.assertEqual(opt.encode_value(60, "PXEClient"), b"PXEClient")
        self.assertEqual(opt.encode_value(43, "01:02"), b"\x01\x02")

    def test_value_decoding_by_option(self):
        self.assertEqual(opt.decode_value(1, b"\xff\xff\xff\x00"), "255.255.255.0")
        self.assertEqual(opt.decode_value(51, b"\x00\x00\xa8\xc0"), 43200)
        self.assertEqual(opt.decode_value(55, b"\x01\x03\x06"), [1, 3, 6])
        # An address-list option is a list even with one address in it.
        self.assertEqual(opt.decode_value(3, b"\x0a\x63\x00\x01"), ["10.99.0.1"])
        self.assertEqual(opt.decode_value(175, b"\xab\xcd"), "ab:cd")

    def test_the_option_area(self):
        blob = opt.pack_options([(53, b"\x02"), (54, b"\x0a\x00\x00\x01")])
        self.assertTrue(blob.endswith(b"\xff"))
        self.assertEqual(opt.unpack_options(blob)[54], b"\x0a\x00\x00\x01")
        # Magic cookie, padding, no END; and RFC 3396 split options.
        self.assertEqual(opt.unpack_options(opt.MAGIC + b"\x00" + bytes([53, 1, 5])),
                         {53: b"\x05"})
        split = bytes([60, 2]) + b"PX" + bytes([60, 7]) + b"EClient"
        self.assertEqual(opt.unpack_options(split)[60], b"PXEClient")

    def test_name_lists_follow_pointers_and_never_loop(self):
        self.assertEqual(opt.decode_value(119, b"\x03foo\x03com\x00\x03bar\xc0\x04"),
                         ["foo.com", "bar.com"])
        self.assertEqual(opt.decode_value(119, b"\x03foo\xc0\x00"),
                         "03:66:6f:6f:c0:00")
        self.assertEqual(opt.decode_value(119, b"\x09foo"), "09:66:6f:6f")


class ClientFqdn(unittest.TestCase):
    """Option 81, RFC 4702."""

    def test_flags_come_from_a_prefix_of_flag_letters_only(self):
        self.assertEqual(opt.encode_fqdn("node01"), b"\x00\x00\x00node01")
        self.assertEqual(opt.encode_fqdn("SO:node01")[0], 0x03)
        self.assertEqual(opt.decode_fqdn(opt.encode_fqdn("host:1")), (0, "host:1"))
        self.assertEqual(opt.decode_fqdn(opt.encode_fqdn("SX:n")), (0, "SX:n"))
        self.assertRaises(ConfigError, opt.fqdn_flag_bits, "SX")

    def test_the_e_flag_sends_wire_format(self):
        raw = opt.encode_fqdn("SE:node01.cluster")
        self.assertEqual(raw[3:], b"\x06node01\x07cluster\x00")
        self.assertEqual(opt.decode_fqdn(raw), (0x05, "node01.cluster"))

    def test_decoding_gives_the_name_and_a_short_option_stays_hex(self):
        self.assertEqual(opt.decode_value(81, b"\x03\x00\x00n1."), "n1.")
        self.assertEqual(opt.decode_value(81, b"\x03\x00"), "03:00")
        self.assertEqual(opt.fqdn_flag_letters(0), "-")


class _FakeFrame(object):
    """Enough of a scapy frame for `decode`."""

    def __init__(self, option_area):
        self.payload = option_area
        self.xid = 0x1234
        self.yiaddr, self.siaddr = "10.0.0.2", "10.0.0.1"
        self.ciaddr = self.giaddr = "0.0.0.0"
        self.chaddr = b"\x02\x00\x11\x22\x33\x44" + b"\x00" * 10
        self.file = b"pxelinux.0" + b"\x00" * 118
        self.sname = b"\x00" * 64
        self.secs = self.flags = 0

    def __getitem__(self, _layer):
        return self

    def haslayer(self, _layer):
        return False


class Decoding(unittest.TestCase):

    def test_a_dhcp_reply_is_named_by_option_53(self):
        reply = opt.decode(_FakeFrame(opt.pack_options([(53, b"\x02")])))
        self.assertEqual(reply.fields["msgtype"], "OFFER")
        self.assertEqual(reply.fields["chaddr"], "02:00:11:22:33:44")

    def test_a_reply_with_no_option_53_is_plain_bootp(self):
        reply = opt.decode(_FakeFrame(opt.MAGIC + b"\xff"))
        self.assertEqual(reply.fields["msgtype"], "BOOTREPLY")
        self.assertEqual(reply.bootfile(), "pxelinux.0")

    def test_known_fields(self):
        for name in ("address", "bootfile", "fqdn_flags", "yiaddr", "opt67",
                     "server_id", "option:3", "12"):
            self.assertTrue(opt.known_field(name), name)
        self.assertFalse(opt.known_field("sha256"))


class Transitions(unittest.TestCase):

    def test_the_table(self):
        self.assertEqual(dhcp.STEP_TYPES, set(["discover", "bootrequest",
                                                "request", "renew", "rebind",
                                                "release"]))
        self.assertIsNone(dhcp.transition(dhcp.BOUND, "discover"))
        self.assertTrue(dhcp.transition(dhcp.BOUND, "renew").unicast)
        self.assertFalse(dhcp.transition(dhcp.BOUND, "rebind").unicast)
        self.assertEqual(dhcp.transition(dhcp.INIT, "bootrequest").next_state,
                         dhcp.INIT)

    def test_advance(self):
        request = dhcp.transition(dhcp.SELECTING, "request")
        self.assertEqual(dhcp.advance(dhcp.SELECTING, request, False),
                         dhcp.SELECTING)
        self.assertEqual(dhcp.advance(dhcp.SELECTING, request, True, "NAK"),
                         dhcp.INIT)
        self.assertEqual(dhcp.advance(dhcp.SELECTING, request, True, "ACK"),
                         dhcp.BOUND)
        release = dhcp.transition(dhcp.BOUND, "release")
        self.assertEqual(dhcp.advance(dhcp.BOUND, release, False), dhcp.INIT)


def reply(msgtype, server="10.0.0.1", yiaddr="10.0.0.101", xid=0):
    fields = {"msgtype": msgtype, "xid": xid, "yiaddr": yiaddr,
              "siaddr": server, "ciaddr": "0.0.0.0", "giaddr": "0.0.0.0",
              "chaddr": "", "file": "", "sname": "", "secs": 0, "flags": 0,
              "src_ip": server, "src_mac": ""}
    return opt.DhcpReply(fields, {54: server, 51: 600})


class FakeWire(object):
    """Answers each send with the next list of replies."""

    scapy = None

    def __init__(self, *answers):
        self.answers = list(answers)
        self.sent = 0

    def send(self, frame):
        self.sent += 1

    def collect(self, session, deadline):
        return self.answers.pop(0) if self.answers else []

    def close(self):
        pass


class StepLoop(unittest.TestCase):

    def setUp(self):
        original = dhcp.build_frame
        dhcp.build_frame = lambda *args: None
        self.addCleanup(setattr, dhcp, "build_frame", original)

    def step(self, text):
        scenario, = config.load([context.write_conf(
            self, "[scenario s]\n" + text)])
        return scenario.steps

    def test_a_discover_binds_the_offer_and_counts_servers_once(self):
        step, = self.step("[step d]\ntype = discover\n")
        first = reply("OFFER")
        session = dhcp.Session(FakeWire([first, reply("OFFER"),
                                         reply("OFFER", "10.0.0.2")]))
        ctx = subst.Context()
        got, extras, sent = dhcp.run_step(step, session, ctx, 0.1, 3)
        self.assertIs(got, first)
        self.assertIs(ctx.get("offer"), first)
        self.assertEqual(extras["offers"], 2)
        self.assertEqual(session.state, dhcp.SELECTING)
        self.assertEqual(session.wire.sent, 1)
        self.assertTrue(sent.startswith("DISCOVER mac=02:"))

    def test_silence_retransmits_and_leaves_the_state(self):
        step, = self.step("[step d]\ntype = discover\n")
        session = dhcp.Session(FakeWire())
        got, extras, _ = dhcp.run_step(step, session, subst.Context(), 0.1, 3)
        self.assertIsNone(got)
        self.assertEqual(session.wire.sent, 3)
        self.assertEqual(session.state, dhcp.INIT)

    def test_a_nak_is_reported_as_a_nak_and_does_not_bind_the_lease(self):
        _, step = self.step("[step d]\ntype = discover\n[step r]\n"
                            "type = request\nrequested_address = 10.0.0.9\n")
        session = dhcp.Session(FakeWire([reply("NAK")]))
        session.state = dhcp.SELECTING
        ctx = subst.Context()
        got, extras, _ = dhcp.run_step(step, session, ctx, 0.1, 1)
        self.assertEqual(got.fields["msgtype"], "NAK")
        self.assertRaises(ConfigError, ctx.get, "lease")
        self.assertEqual(session.state, dhcp.INIT)

    def test_an_ack_binds_the_lease_and_arms_arp(self):
        _, step = self.step("[step d]\ntype = discover\n[step r]\n"
                            "type = request\n")
        session = dhcp.Session(FakeWire([reply("ACK")]))
        session.state = dhcp.SELECTING
        ctx = subst.Context()
        dhcp.run_step(step, session, ctx, 0.1, 1)
        self.assertEqual(ctx.get("lease").fields["yiaddr"], "10.0.0.101")
        self.assertEqual(session.leases, set(["10.0.0.101"]))
        self.assertEqual(session.state, dhcp.BOUND)

    def test_a_step_mac_replaces_the_random_one(self):
        step, = self.step("[step d]\ntype = discover\nmac = 02-00-00-00-00-AA\n")
        session = dhcp.Session(FakeWire())
        dhcp.run_step(step, session, subst.Context(), 0.1, 1)
        self.assertEqual(session.mac, "02:00:00:00:00:aa")


@unittest.skipUnless(scapy, "scapy is not installed")
class Frames(unittest.TestCase):
    """A real frame, serialised and read back. Needs scapy, not root."""

    CONF = """
[scenario s]
[step d]
type            = discover
mac             = 02:00:de:ad:be:ef
vendor_class    = PXEClient:Arch:00011:UNDI:003000
client_arch     = 0x000b
user_class      = xNBA
user_class_form = rfc3004
request_options = 1, 3, 6, 43, 54, 60, 66, 67
max_message_size = 1260
hostname        = probe
fqdn            = N:probe.cluster.local
[step renew]
type      = renew
ciaddr    = 10.0.0.101
server_id = 10.0.0.1
"""

    def setUp(self):
        scenario, = config.load([context.write_conf(self, self.CONF)])
        self.discover, self.renew = scenario.steps
        self.session = dhcp.Session(None)
        self.session.mac = "02:00:de:ad:be:ef"
        self.session.xid = 0x1234

    def frame(self, step, state=dhcp.INIT):
        return dhcp.build_frame(step, self.session,
                                dhcp.transition(state, step.type),
                                subst.Context(), scapy)

    def test_a_discover_is_broadcast_and_carries_every_option_shape(self):
        frame = self.frame(self.discover)
        self.assertEqual(frame["Ether"].dst, "ff:ff:ff:ff:ff:ff")
        self.assertEqual((frame["IP"].src, frame["IP"].dst),
                         ("0.0.0.0", "255.255.255.255"))
        self.assertEqual((frame["UDP"].sport, frame["UDP"].dport), (68, 67))
        self.assertEqual(int(frame["BOOTP"].flags), 0x8000)
        self.assertGreaterEqual(len(bytes(frame["BOOTP"])), 300)

        decoded = opt.decode(scapy.Ether(bytes(frame)))
        self.assertEqual(decoded.fields["msgtype"], "DISCOVER")
        self.assertEqual(decoded.fields["xid"], 0x1234)
        self.assertEqual(decoded.options[60], "PXEClient:Arch:00011:UNDI:003000")
        self.assertEqual(decoded.options[93], 11)
        self.assertEqual(decoded.options[57], 1260)
        self.assertEqual(decoded.options[55], [1, 3, 6, 43, 54, 60, 66, 67])
        self.assertEqual(decoded.options[61], "01:02:00:de:ad:be:ef")
        self.assertEqual(decoded.options[81], "probe.cluster.local")
        self.assertEqual(decoded.fqdn_flags(), "N")
        raw = opt.unpack_options(bytes(frame["BOOTP"].payload))
        self.assertEqual(raw[77], b"\x04xNBA")

    def test_a_raw_user_class_is_not_prefixed(self):
        self.discover.params["user_class_form"] = "raw"
        raw = opt.unpack_options(bytes(self.frame(self.discover)["BOOTP"].payload))
        self.assertEqual(raw[77], b"xNBA")

    def test_a_renew_is_unicast_to_the_server(self):
        frame = self.frame(self.renew, dhcp.BOUND)
        self.assertEqual((frame["IP"].src, frame["IP"].dst),
                         ("10.0.0.101", "10.0.0.1"))
        self.assertEqual(int(frame["BOOTP"].flags), 0)


if __name__ == "__main__":
    unittest.main()
