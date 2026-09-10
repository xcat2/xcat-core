"""Build a real frame and read it back.

This is the one test that needs scapy, so it skips where scapy is absent. It
needs neither root nor a network: the frame is serialised, reparsed and
decoded in memory, which is enough to catch a mis-encoded option or a scapy
API that moved under us.
"""

import os
import tempfile
import unittest

import helper

from dhcptest_lib import config
from dhcptest_lib import options as opt

try:
    from scapy.all import Ether
    from dhcptest_lib import runner
    HAVE_SCAPY = True
except ImportError:                                # pragma: no cover
    HAVE_SCAPY = False

CONF = """
[scenario wire]
description = a PXE discover carrying every option shape

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
expect          = offer
"""


@unittest.skipUnless(HAVE_SCAPY, "scapy is not installed")
class RoundTrip(unittest.TestCase):

    def setUp(self):
        directory = tempfile.mkdtemp(prefix="dhcptest-")
        path = os.path.join(directory, "wire.conf")
        with open(path, "w") as handle:
            handle.write(CONF)
        scenarios, _ = config.load([path])
        self.step = scenarios[0].step("d")
        self.session = runner.Session("02:00:de:ad:be:ef", "lo")
        self.context = runner.Context()
        self.frame = runner.build_packet(
            self.step, self.session, self.context, "discover", runner._scapy())
        self.reply = opt.decode(Ether(bytes(self.frame)))

    def test_the_frame_survives_serialisation(self):
        self.assertEqual(self.reply.msgtype, "DISCOVER")
        self.assertEqual(self.reply.xid, self.session.xid)
        self.assertEqual(self.reply.chaddr.lower(), "02:00:de:ad:be:ef")

    def test_it_is_broadcast_from_an_unconfigured_client(self):
        frame = self.frame
        self.assertEqual(frame["Ether"].dst, "ff:ff:ff:ff:ff:ff")
        self.assertEqual(frame["IP"].src, "0.0.0.0")
        self.assertEqual(frame["IP"].dst, "255.255.255.255")
        self.assertEqual(frame["UDP"].sport, 68)
        self.assertEqual(frame["UDP"].dport, 67)
        self.assertEqual(int(frame["BOOTP"].flags), 0x8000)

    def test_every_option_shape_encodes_and_decodes(self):
        options = self.reply.options
        self.assertEqual(options[60], "PXEClient:Arch:00011:UNDI:003000")  # text
        self.assertEqual(options[93], 11)                                  # u16
        self.assertEqual(options[57], 1260)                                # u16
        self.assertEqual(options[12], "probe")                             # text
        self.assertEqual(options[55], [1, 3, 6, 43, 54, 60, 66, 67])       # list
        self.assertEqual(options[61], "01:02:00:de:ad:be:ef")              # hex

    def test_rfc3004_user_class_is_length_prefixed(self):
        raw = opt.unpack_options(bytes(self.frame["BOOTP"].payload))[77]
        self.assertEqual(raw, b"\x04xNBA")

    def test_a_raw_user_class_is_not_prefixed(self):
        self.step.params["user_class_form"] = "raw"
        frame = runner.build_packet(self.step, self.session, self.context,
                                    "discover", runner._scapy())
        raw = opt.unpack_options(bytes(frame["BOOTP"].payload))[77]
        self.assertEqual(raw, b"xNBA")

    def test_the_message_is_padded_to_the_minimum_size(self):
        # Some relays and older servers drop a short BOOTP frame.
        payload = bytes(self.frame["BOOTP"])
        self.assertGreaterEqual(len(payload), 300)

    def test_a_unicast_renew_is_addressed_to_the_server(self):
        step = config.load([self._write("""
[scenario r]
[step renew]
type      = renew
ciaddr    = 10.0.0.101
server_id = 10.0.0.1
""")])[0][0].step("renew")
        self.session.state = "BOUND"
        frame = runner.build_packet(step, self.session, self.context, "request",
                                    runner._scapy())
        self.assertEqual(frame["IP"].dst, "10.0.0.1")
        self.assertEqual(frame["IP"].src, "10.0.0.101")
        self.assertEqual(int(frame["BOOTP"].flags), 0)
        self.assertEqual(frame["BOOTP"].ciaddr, "10.0.0.101")

    def test_one_server_heard_twice_counts_once(self):
        # A retransmit reuses the xid, so an answer to the first attempt still
        # matches the second. `offers` counts servers, not packets.
        from dhcptest_lib.model import Reply
        first = Reply(msgtype="OFFER", yiaddr="10.0.0.101", src_ip="10.0.0.1",
                      options={54: "10.0.0.1"})
        again = Reply(msgtype="OFFER", yiaddr="10.0.0.101", src_ip="10.0.0.1",
                      options={54: "10.0.0.1"})
        other = Reply(msgtype="OFFER", yiaddr="10.0.0.7", src_ip="10.0.0.2",
                      options={54: "10.0.0.2"})
        self.assertEqual(len(runner._distinct([first, again])), 1)
        self.assertEqual(len(runner._distinct([first, again, other])), 2)

    def _write(self, text):
        directory = tempfile.mkdtemp(prefix="dhcptest-")
        path = os.path.join(directory, "t.conf")
        with open(path, "w") as handle:
            handle.write(text)
        return path


if __name__ == "__main__":
    unittest.main()
