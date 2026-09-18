"""The assertion language and `$step.field` substitution."""

import unittest

import context  # noqa: F401

from blackboxtest_lib import assertions, subst
from blackboxtest_lib.dhcpopts import DhcpReply
from blackboxtest_lib.errors import ConfigError
from blackboxtest_lib.model import Reply


def check(line, reply, extras=None, ctx=None):
    return assertions.evaluate(assertions.parse(line), reply,
                               ctx or subst.Context(), extras)


def offer(options=None):
    fields = {"msgtype": "OFFER", "xid": 7, "yiaddr": "10.0.0.101",
              "siaddr": "10.0.0.1", "ciaddr": "0.0.0.0", "giaddr": "0.0.0.0",
              "chaddr": "02:00:00:00:00:01", "file": "", "sname": "",
              "secs": 0, "flags": 0, "src_ip": "10.0.0.1", "src_mac": ""}
    base = {54: "10.0.0.1", 51: 600}
    base.update(options or {})
    return DhcpReply(fields, base)


DNS = Reply("dns", {"status": "NOERROR", "data": ["10.0.0.11", "10.0.1.11"],
                    "count": 2, "header": {"content-type": "text/plain"},
                    "empty": [], "text": "line one\nlinux /boot/k\n"})


class Parsing(unittest.TestCase):

    def test_the_three_shapes(self):
        self.assertEqual(assertions.parse("x present").value, None)
        self.assertEqual(assertions.parse("x ==").value, "")
        self.assertEqual(assertions.parse("x contains a b c").value, "a b c")

    def test_what_is_refused(self):
        for line in ("x", "x ~= 1", "x present 1", "x matches ("):
            self.assertRaises(ConfigError, assertions.parse, line)

    def test_blank_and_comment_lines_are_skipped(self):
        block = "\n  # note\n  x == 1\n\n  y present\n"
        self.assertEqual(len(assertions.parse_block(block)), 2)


class Comparison(unittest.TestCase):

    def test_equality_is_address_then_number_then_text(self):
        self.assertTrue(check("yiaddr == 10.0.0.101", offer()).ok)
        self.assertTrue(check("51 == 0x258", offer()).ok)
        self.assertTrue(check("status == NOERROR", DNS).ok)
        self.assertFalse(check("status == noerror", DNS).ok)

    def test_a_list_means_any_element_or_the_whole(self):
        self.assertTrue(check("data == 10.0.1.11", DNS).ok)
        self.assertTrue(check("data == 10.0.0.11, 10.0.1.11", DNS).ok)
        self.assertFalse(check("data == 10.0.2.11", DNS).ok)

    def test_membership_of_a_cidr_a_range_and_a_list(self):
        self.assertTrue(check("yiaddr in 10.0.0.0/24", offer()).ok)
        self.assertTrue(check("yiaddr in 10.0.0.100-10.0.0.110", offer()).ok)
        self.assertFalse(check("yiaddr in 10.0.0.102-10.0.0.110", offer()).ok)
        self.assertTrue(check("status in NXDOMAIN, NOERROR", DNS).ok)
        self.assertTrue(check("status not-in SERVFAIL, REFUSED", DNS).ok)

    def test_text_and_numeric_operators(self):
        self.assertTrue(check("text matches ^linux\\s", DNS).ok)
        self.assertTrue(check("text contains /boot/k", DNS).ok)
        self.assertTrue(check("status starts-with NO", DNS).ok)
        self.assertTrue(check("status ends-with ERROR", DNS).ok)
        self.assertTrue(check("count >= 2", DNS).ok)
        self.assertFalse(check("status > 2", DNS).ok)

    def test_indexing_and_mapping(self):
        self.assertTrue(check("data.1 == 10.0.1.11", DNS).ok)
        self.assertTrue(check("header.content-type == text/plain", DNS).ok)
        self.assertFalse(check("data.5 present", DNS).ok)


class Presence(unittest.TestCase):

    def test_an_empty_list_and_a_zeroed_header_are_absence(self):
        self.assertTrue(check("empty absent", DNS).ok)
        self.assertTrue(check("giaddr absent", offer()).ok)
        self.assertTrue(check("yiaddr present", offer()).ok)

    def test_no_boot_file_is_absent_not_empty(self):
        self.assertTrue(check("bootfile absent", offer()).ok)
        self.assertFalse(check("bootfile matches ^$", offer()).ok)

    def test_a_negative_comparison_holds_against_an_absent_target(self):
        self.assertTrue(check("bootfile != http://x/nodes/n1", offer()).ok)
        self.assertTrue(check("67 not-in a, b", offer()).ok)
        self.assertFalse(check("bootfile == x", offer()).ok)

    def test_no_reply_fails_every_positive_assertion(self):
        result = check("msgtype == OFFER", None)
        self.assertFalse(result.ok)
        self.assertIn("not present", result.detail)
        self.assertTrue(check("msgtype absent", None).ok)

    def test_meta_targets_come_from_the_runner(self):
        self.assertTrue(check("offers == 1", None, {"offers": 1}).ok)
        self.assertFalse(check("attempt present", DNS).ok)


class DhcpFields(unittest.TestCase):

    def test_options_by_number_name_and_prefix(self):
        reply = offer()
        for target in ("54", "option:54", "server_id", "opt54"):
            self.assertTrue(check("%s == 10.0.0.1" % target, reply).ok, target)

    def test_the_boot_file_prefers_option_67(self):
        reply = offer({67: "grub2.aarch64"})
        reply.fields["file"] = "pxelinux.0"
        self.assertTrue(check("bootfile == grub2.aarch64", reply).ok)
        self.assertTrue(check("file == pxelinux.0", reply).ok)

    def test_the_dns_name_prefers_option_81_and_falls_back_to_12(self):
        self.assertTrue(check("dns_name == n1", offer({12: "n1"})).ok)
        self.assertTrue(check("dns_name == n2",
                              offer({12: "n1", 81: "n2"})).ok)
        self.assertTrue(check("dns_name absent", offer()).ok)

    def test_fqdn_flags_are_read_from_the_raw_option(self):
        from blackboxtest_lib import dhcpopts
        raw = dhcpopts.pack_options([(81, dhcpopts.encode_fqdn("SO:n1"))])
        reply = offer({81: "n1"})
        reply.raw_options = raw
        self.assertTrue(check("fqdn_flags == SO", reply).ok)
        self.assertTrue(check("fqdn_flags absent", offer()).ok)


class Substitution(unittest.TestCase):

    def test_references_and_variables_are_found_apart(self):
        text = "%(net)s $offer.address $config.header.content-type."
        self.assertEqual(subst.references(text),
                         [("offer", "address"),
                          ("config", "header.content-type")])
        self.assertEqual(subst.variables(text), set(["net"]))

    def test_a_reference_resolves_against_an_earlier_reply(self):
        ctx = subst.Context()
        ctx.bind("offer", offer())
        ctx.bind("q", DNS)
        self.assertEqual(subst.resolve("ip=$offer.address", ctx), "ip=10.0.0.101")
        self.assertEqual(subst.resolve("$q.data", ctx), "10.0.0.11")
        self.assertTrue(check("$offer.server_id == 10.0.0.1", None, ctx=ctx).ok)

    def test_an_unbound_name_or_missing_field_is_a_config_error(self):
        ctx = subst.Context()
        ctx.bind("offer", offer())
        self.assertRaisesRegex(ConfigError, "nothing has bound",
                               subst.resolve, "$ack.address", ctx)
        self.assertRaisesRegex(ConfigError, "no option 67",
                               subst.resolve, "$offer.opt67", ctx)

    def test_format_value(self):
        self.assertEqual(subst.format_value(True), "yes")
        self.assertEqual(subst.format_value(b"k"), "k")
        self.assertEqual(subst.format_value(["a", 1]), "a, 1")
        self.assertEqual(subst.format_value({"b": 1, "a": 2}), "a=2, b=1")


if __name__ == "__main__":
    unittest.main()
