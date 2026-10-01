"""TAP output, exit codes, and the address helpers the fixtures call."""

import io
import unittest

import context  # noqa: F401

from blackboxtest_lib import netutil, report
from blackboxtest_lib.errors import ConfigError
from blackboxtest_lib.model import Reply


def tap(*records):
    stream = io.StringIO()
    reporter = report.TapReporter(stream)
    reporter.start()
    for record in records:
        reporter.add(record)
    reporter.finish()
    return stream.getvalue(), reporter.exit_code()


class Tap(unittest.TestCase):

    def test_a_pass_is_one_line_and_the_plan_counts_it(self):
        text, code = tap(report.Record("s", "t", "size > 0", True))
        self.assertEqual(text, "TAP version 13\nok 1 - s/t: size > 0\n1..1\n"
                               "# passed 1, failed 0, skipped 0\n")
        self.assertEqual(code, 0)

    def test_a_failure_explains_itself_on_single_lines(self):
        reply = Reply("dns", {"status": "NXDOMAIN"}, ok=False)
        text, code = tap(report.Record(
            "s", "ptr", "data contains n1", False, expected="n1", actual=None,
            detail="data is not\npresent", reply=reply, sent="dig @x y PTR",
            attempt=2, attempts=2))
        self.assertEqual(code, 1)
        self.assertIn("not ok 1 - s/ptr: data contains n1\n  ---\n", text)
        for line in ("  expected: 'n1'", "  received: None",
                     "  detail: data is not present", "  sent: dig @x y PTR",
                     "  attempt: 2 of 2", "  reply: dns failed status=NXDOMAIN"):
            self.assertIn(line + "\n", text)

    def test_a_skip_is_ok_and_neither_passes_nor_fails(self):
        text, code = tap(report.Record("s", "t", "x", True, skip_reason="no nic"))
        self.assertIn("ok 1 - s/t: x # SKIP no nic\n", text)
        self.assertIn("# passed 0, failed 0, skipped 1", text)
        self.assertEqual(code, 0)


class Addresses(unittest.TestCase):

    def test_the_names_a_loader_asks_for(self):
        self.assertEqual(netutil.hex_ip("10.99.1.11"), "0A63010B")
        self.assertEqual(netutil.hex_net("10.99.1.0", 24), "0A6301")
        self.assertEqual(netutil.hex_net("10.99.1.0", "20"), "0A630")
        self.assertRaises(ValueError, netutil.hex_net, "10.99.1.0", 33)
        self.assertRaises(ValueError, netutil.hex_ip, "10.99.1")
        self.assertEqual(netutil.reverse_name("10.99.1.11"),
                         "11.1.99.10.in-addr.arpa")

    def test_mac_forms(self):
        for text in ("02:AA:bb:0c:0d:0e", "02-aa-bb-0c-0d-0e", "02aabb0c0d0e",
                     "2:aa:bb:c:d:e"):
            self.assertEqual(netutil.normalise_mac(text), "02:aa:bb:0c:0d:0e")
        self.assertEqual(netutil.dashed_mac("02:aa:bb:0c:0d:0e"),
                         "02-aa-bb-0c-0d-0e")
        for bad in ("02:aa:bb", "02:aa:bb:0c:0d:0e:0f", "zz:aa:bb:0c:0d:0e"):
            self.assertRaises(ConfigError, netutil.normalise_mac, bad)
        self.assertEqual(netutil.random_mac()[:3], "02:")

    def test_membership(self):
        self.assertTrue(netutil.ip_in("10.0.0.5", "10.0.0.0/24"))
        self.assertTrue(netutil.ip_in_range("10.0.0.5", "10.0.0.9-10.0.0.1"))
        self.assertFalse(netutil.ip_in("x", "10.0.0.0/24"))
        self.assertIsNone(netutil.parse_range("a-b"))


if __name__ == "__main__":
    unittest.main()
