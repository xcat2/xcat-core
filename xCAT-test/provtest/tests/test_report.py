"""Output, and the address arithmetic the scenarios rely on.

CI reads TAP and nothing else, so the shape of a failing line is as much a part
of this tool's contract as any assertion. A failure has to be understandable
from the log alone: by the time anyone reads a CI result, the network it ran on
no longer exists.
"""

import io
import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import netutil, report
from provtest_lib.errors import EXIT_FAILED, EXIT_OK
from provtest_lib.model import Reply


def record(ok=True, **kwargs):
    kwargs.setdefault("scenario", "node-reverse")
    kwargs.setdefault("step", "ptr")
    kwargs.setdefault("description", "the address resolves to its name")
    return report.Record(ok=ok, **kwargs)


def run(reporter, records):
    reporter.start()
    for item in records:
        reporter.add(item)
    reporter.finish()
    return reporter.stream.getvalue()


class TapTests(unittest.TestCase):

    def tap(self, records):
        return run(report.TapReporter(io.StringIO()), records)

    def test_a_pass_is_one_ok_line(self):
        text = self.tap([record()])
        self.assertIn("TAP version 13\n", text)
        self.assertIn("ok 1 - node-reverse/ptr: the address resolves to its name",
                      text)
        self.assertIn("1..1\n", text)

    def test_the_plan_counts_every_record(self):
        text = self.tap([record(), record(), record()])
        self.assertIn("1..3\n", text)
        self.assertIn("# passed 3, failed 0, skipped 0\n", text)

    def test_a_failure_says_not_ok_and_explains_itself(self):
        text = self.tap([record(
            ok=False, expected="provtestcn.provtest.cluster",
            actual="(no answer records)",
            sent="dig @10.99.1.1 -b 10.99.1.11 PTR 11.1.99.10.in-addr.arpa",
            reply=Reply(kind="dns", fields={"status": "NXDOMAIN"}, ok=False))])
        self.assertIn("not ok 1 - ", text)
        self.assertIn("---", text)
        self.assertIn("...", text)
        # The command as it was sent: the first thing an operator does after a
        # failure is run it again by hand.
        self.assertIn("dig @10.99.1.1 -b 10.99.1.11 PTR", text)
        self.assertIn("provtestcn.provtest.cluster", text)
        self.assertIn("no answer records", text)

    def test_a_pass_carries_no_diagnostic(self):
        self.assertNotIn("---", self.tap([record()]))

    def test_a_skip_is_ok_with_a_reason(self):
        text = self.tap([record(ok=False, skip_reason="tftp is not installed")])
        self.assertIn("ok 1 - ", text)
        self.assertIn("# SKIP tftp is not installed", text)
        self.assertNotIn("not ok", text)

    def test_a_skip_counts_as_neither_a_pass_nor_a_failure(self):
        reporter = report.TapReporter(io.StringIO())
        run(reporter, [record(), record(ok=False, skip_reason="no client")])
        self.assertEqual((reporter.passed, reporter.failed, reporter.skipped),
                         (1, 0, 1))


class ExitCodeTests(unittest.TestCase):

    def test_all_passing_is_zero(self):
        reporter = report.TapReporter(io.StringIO())
        run(reporter, [record(), record()])
        self.assertEqual(reporter.exit_code(), EXIT_OK)

    def test_one_failure_is_one(self):
        reporter = report.TapReporter(io.StringIO())
        run(reporter, [record(), record(ok=False)])
        self.assertEqual(reporter.exit_code(), EXIT_FAILED)

    def test_a_skip_alone_is_not_a_failure(self):
        reporter = report.TapReporter(io.StringIO())
        run(reporter, [record(ok=False, skip_reason="no client")])
        self.assertEqual(reporter.exit_code(), EXIT_OK)


class OtherFormatTests(unittest.TestCase):

    def test_every_declared_format_can_be_built(self):
        for name in report.REPORTERS:
            self.assertIsNotNone(report.make(name, io.StringIO()))

    def test_an_unknown_format_is_refused(self):
        self.assertRaises(ValueError, report.make, "xml", io.StringIO())

    def test_pretty_groups_by_scenario_and_summarises(self):
        text = run(report.PrettyReporter(io.StringIO()),
                   [record(), record(ok=False, step="a", description="d")])
        self.assertIn("PASS ptr", text)
        self.assertIn("FAIL a", text)
        self.assertIn("total=2 passed=1 failed=1 skipped=0", text)

    def test_json_is_one_parsable_object(self):
        import json

        text = run(report.JsonReporter(io.StringIO()),
                   [record(), record(ok=False)])
        payload = json.loads(text)
        self.assertEqual(payload["total"], 2)
        self.assertEqual(payload["failed"], 1)
        self.assertEqual(len(payload["records"]), 2)


class AddressTests(unittest.TestCase):
    """The encodings a loader asks for its files by."""

    def test_hex_ip_is_what_a_loader_asks_for(self):
        # 10.99.1.11 is grub.cfg-0A63010B. A digit wrong here produces no error
        # anywhere, just a node sitting at the loader.
        self.assertEqual(netutil.hex_ip("10.99.1.11"), "0A63010B")
        self.assertEqual(netutil.hex_ip("10.99.1.11", upper=False), "0a63010b")

    def test_hex_ip_of_a_network_address(self):
        self.assertEqual(netutil.hex_ip("10.99.1.0"), "0A630100")

    def test_a_per_network_config_is_named_by_the_prefix_only(self):
        # 10.99.1.0/24 is 0A6301, not 0A630100: the file is named by as many
        # digits as the netmask covers. Asking for all eight gets a machine
        # with no definition nothing at all, which is the whole failure this
        # stage exists to catch.
        self.assertEqual(netutil.hex_net("10.99.1.0", 24), "0A6301")
        self.assertEqual(netutil.hex_net("10.99.0.0", 16), "0A63")
        self.assertEqual(netutil.hex_net("10.99.1.0", 26), "0A63010")
        self.assertEqual(netutil.hex_net("10.99.1.0", 24, upper=False), "0a6301")

    def test_a_prefix_that_is_not_one_is_refused(self):
        self.assertRaises(ValueError, netutil.hex_net, "10.99.1.0", 33)
        self.assertRaises(ValueError, netutil.hex_net, "10.99.1.0", "wide")

    def test_hex_ip_rejects_what_is_not_an_address(self):
        self.assertRaises(ValueError, netutil.hex_ip, "provtestcn")

    def test_the_reverse_name_is_the_one_dig_is_asked_for(self):
        self.assertEqual(netutil.reverse_name("10.99.1.11"),
                         "11.1.99.10.in-addr.arpa")

    def test_a_mac_normalises_to_the_colon_form(self):
        for text in ("52:54:00:DC:11:01", "52-54-00-dc-11-01",
                     "52.54.00.dc.11.01", "52:54:0:dc:11:1"):
            self.assertEqual(netutil.normalise_mac(text), "52:54:00:dc:11:01")

    def test_a_mac_becomes_the_dashed_form_a_config_is_named_by(self):
        self.assertEqual(netutil.dashed_mac("52:54:00:DC:11:01"),
                         "52-54-00-dc-11-01")

    def test_a_mac_of_the_wrong_length_is_refused(self):
        self.assertRaises(ValueError, netutil.normalise_mac, "52:54:00:dc:11")
        self.assertRaises(ValueError, netutil.normalise_mac, "not a mac")

    def test_membership_helpers(self):
        self.assertTrue(netutil.ip_in("10.99.1.11", "10.99.1.0/24"))
        self.assertFalse(netutil.ip_in("10.99.2.11", "10.99.1.0/24"))
        self.assertTrue(netutil.ip_in_range("10.99.1.11", "10.99.1.1-10.99.1.20"))
        self.assertFalse(netutil.ip_in_range("10.99.1.21", "10.99.1.1-10.99.1.20"))

    def test_nonsense_is_not_a_member_of_anything(self):
        self.assertFalse(netutil.ip_in("provtestcn", "10.99.1.0/24"))
        self.assertFalse(netutil.ip_in("10.99.1.11", "not a network"))


if __name__ == "__main__":
    unittest.main()
