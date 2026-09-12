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

    def test_a_reply_naming_no_boot_file_is_absent_not_empty(self):
        # A server that hands out no boot file sends an empty `file` header and
        # no option 67. "Nothing to fetch" is therefore written `bootfile
        # absent`: a regex against an empty string can never hold, so a
        # scenario written that way would fail whatever the server did.
        nothing = offer(file="", options={54: "10.0.0.1"})
        self.assertTrue(self.check("bootfile absent", nothing).ok)
        self.assertFalse(self.check("bootfile present", nothing).ok)
        self.assertFalse(self.check("bootfile matches ^$", nothing).ok)
        self.assertTrue(self.check("bootfile present").ok)

    def test_a_negative_comparison_holds_against_a_target_that_is_absent(self):
        # "is not the node's install script" is satisfied by a reply that names
        # no boot file at all -- which is the strongest way a server can
        # satisfy it. The same reading applies to `not-in`. Everything else
        # still fails on an absent target, because there is nothing to compare.
        nothing = offer(file="", options={54: "10.0.0.1"})
        self.assertTrue(self.check("bootfile != pxelinux.0", nothing).ok)
        self.assertTrue(self.check("option:67 != pxelinux.0", nothing).ok)
        self.assertTrue(self.check("option:66 not-in 10.0.0.0/24", nothing).ok)
        self.assertFalse(self.check("bootfile == pxelinux.0", nothing).ok)
        self.assertFalse(self.check("bootfile starts-with http://", nothing).ok)

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

    def test_range_membership(self):
        # A dynamic pool is written as two addresses, not as a CIDR: it rarely
        # lines up on a prefix boundary.
        self.assertTrue(self.check("yiaddr in 10.0.0.100-10.0.0.200").ok)
        self.assertFalse(self.check("yiaddr in 10.0.0.102-10.0.0.200").ok)
        self.assertTrue(self.check("yiaddr not-in 10.0.0.1-10.0.0.50").ok)
        # The bounds are inclusive.
        self.assertTrue(self.check("yiaddr in 10.0.0.101-10.0.0.101").ok)
        # A value with a hyphen that is not two addresses is still a list entry.
        self.assertTrue(self.check("option:60 in PXEClient, some-other").ok)

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


class FqdnFlagsTarget(unittest.TestCase):
    """`fqdn_flags` is a target of its own, because option 81 holds two facts."""

    def _reply(self, raw):
        from dhcptest_lib import options
        blob = options.pack_options([(53, b"\x02"), (81, raw)])
        decoded = dict((code, options.decode_value(code, value))
                       for code, value in options.unpack_options(blob).items())
        return Reply(msgtype="OFFER", options=decoded, raw_options=blob)

    def test_the_flags_and_the_name_are_asserted_separately(self):
        reply = self._reply(b"\x03\x00\x00node01.cluster.local.")
        self.assertTrue(self._ok("fqdn_flags == SO", reply))
        self.assertTrue(self._ok("option:81 == node01.cluster.local.", reply))

    def test_the_dns_name_prefers_option_81_and_falls_back_to_12(self):
        # The two servers put the name in different options. A scenario about
        # the name asserts on one target and holds for both.
        both = self._reply(b"\x03\x00\x00node01.cluster.local.")
        both.options[12] = "node01"
        self.assertEqual(both.dns_name(), "node01.cluster.local.")
        only12 = Reply(msgtype="OFFER", options={12: "node01"})
        self.assertEqual(only12.dns_name(), "node01")
        self.assertTrue(self._ok("dns_name matches ^node01", only12))

    def test_a_reply_naming_the_node_nowhere_has_no_dns_name(self):
        self.assertTrue(
            self._ok("dns_name absent", Reply(msgtype="OFFER", options={53: 2})))

    def test_a_reply_with_no_option_81_has_no_flags(self):
        reply = Reply(msgtype="OFFER", options={53: 2})
        self.assertEqual(reply.fqdn_flags(), "")
        self.assertTrue(self._ok("fqdn_flags absent", reply))

    def _ok(self, text, reply):
        return assertions.evaluate(assertions.parse(text), reply, {}).ok


if __name__ == "__main__":
    unittest.main()
