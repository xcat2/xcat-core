import unittest

import helper                                    # noqa: F401

from dhcptest_lib import assertions
from dhcptest_lib.errors import ConfigError
from dhcptest_lib.model import Reply
from dhcptest_lib.subst import Context


#: Distinguishes "caller passed no reply argument" from "there was no reply".
NOTHING = object()


def offer(**kwargs):
    fields = dict(
        msgtype="OFFER",
        yiaddr="10.0.0.101",
        siaddr="10.0.0.1",
        file="xcat/xnba.kpxe",
        options={54: "10.0.0.1", 51: 43200, 1: "255.255.255.0", 60: "PXEClient"},
    )
    fields.update(kwargs)
    return Reply(**fields)


class Parsing(unittest.TestCase):

    def test_parses_the_three_shapes(self):
        self.assertEqual(assertions.parse("msgtype == OFFER").op, "==")
        self.assertEqual(assertions.parse("option:54 present").value, None)
        self.assertEqual(assertions.parse("yiaddr in 10.0.0.0/24").value,
                         "10.0.0.0/24")

    def test_a_value_may_contain_spaces(self):
        parsed = assertions.parse("file matches ^http://.* end$")
        self.assertEqual(parsed.value, "^http://.* end$")

    def test_empty_value_means_non_empty(self):
        self.assertEqual(assertions.parse("file !=").value, "")

    def test_rejects_unknown_operator_target_and_regex(self):
        self.assertRaises(ConfigError, assertions.parse, "msgtype === OFFER")
        self.assertRaises(ConfigError, assertions.parse, "nonsense == 1")
        self.assertRaises(ConfigError, assertions.parse, "file matches (")
        self.assertRaises(ConfigError, assertions.parse, "option:54 present now")
        self.assertRaises(ConfigError, assertions.parse, "msgtype")

    def test_parse_block_skips_blanks_and_comments(self):
        block = "\nmsgtype == OFFER\n# a comment\n\noffers == 1\n"
        self.assertEqual(len(assertions.parse_block(block)), 2)

    def test_reference_targets_are_checked(self):
        assertions.parse("$offer.address in 10.0.0.0/24")
        self.assertRaises(ConfigError, assertions.parse,
                          "$offer.addres in 10.0.0.0/24")


class Evaluation(unittest.TestCase):

    def setUp(self):
        self.context = Context()

    def check(self, line, reply=NOTHING, extras=None):
        return assertions.evaluate(assertions.parse(line),
                                   offer() if reply is NOTHING else reply,
                                   self.context, extras)

    def test_message_type_and_header_fields(self):
        self.assertTrue(self.check("msgtype == OFFER").ok)
        self.assertTrue(self.check("msgtype != ACK").ok)
        self.assertTrue(self.check("siaddr == 10.0.0.1").ok)
        self.assertFalse(self.check("siaddr == 10.0.0.2").ok)

    def test_options_by_number_and_name(self):
        self.assertTrue(self.check("option:54 == 10.0.0.1").ok)
        self.assertTrue(self.check("option:server_id == 10.0.0.1").ok)
        self.assertTrue(self.check("51 == 43200").ok)

    def test_presence(self):
        self.assertTrue(self.check("option:54 present").ok)
        self.assertTrue(self.check("option:66 absent").ok)
        self.assertFalse(self.check("option:66 present").ok)

    def test_subnet_membership(self):
        self.assertTrue(self.check("yiaddr in 10.0.0.0/24").ok)
        self.assertFalse(self.check("yiaddr in 192.168.0.0/24").ok)
        self.assertTrue(self.check("yiaddr not-in 192.168.0.0/24").ok)

    def test_list_membership(self):
        self.assertTrue(self.check("siaddr in 10.0.0.1, 10.0.0.2").ok)
        self.assertFalse(self.check("siaddr in 10.0.0.3, 10.0.0.2").ok)

    def test_string_operators(self):
        self.assertTrue(self.check("file starts-with xcat/").ok)
        self.assertTrue(self.check("file ends-with .kpxe").ok)
        self.assertTrue(self.check("file contains xnba").ok)
        self.assertTrue(self.check("file matches ^xcat/.*\\.kpxe$").ok)

    def test_numeric_operators(self):
        self.assertTrue(self.check("option:51 > 600").ok)
        self.assertFalse(self.check("option:51 < 600").ok)

    def test_missing_field_fails_with_an_explanation(self):
        result = self.check("option:67 == pxelinux.0")
        self.assertFalse(result.ok)
        self.assertIn("not present", result.detail)

    def test_offers_count_comes_from_extras(self):
        self.assertTrue(self.check("offers == 1", extras={"offers": 1}).ok)
        self.assertFalse(self.check("offers == 1", extras={"offers": 2}).ok)

    def test_a_failure_reports_expected_and_received(self):
        result = self.check("file == pxelinux.0")
        self.assertFalse(result.ok)
        self.assertEqual(result.expected, "pxelinux.0")
        self.assertEqual(result.actual, "xcat/xnba.kpxe")

    def test_no_reply_is_a_failure_not_a_crash(self):
        result = self.check("msgtype == OFFER", reply=None)
        self.assertFalse(result.ok)


if __name__ == "__main__":
    unittest.main()
