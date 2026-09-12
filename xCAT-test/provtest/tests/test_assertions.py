"""The assertion mini-language, checked without a server.

Every case here is a line some shipped scenario writes, evaluated against a
reply built by hand. The point of the module is that a scenario's assertions
mean what their author thought they meant, and that is decidable offline.
"""

import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import assertions
from provtest_lib.errors import ConfigError
from provtest_lib.model import Reply
from provtest_lib.subst import Context


def reply(**fields):
    return Reply(kind="test", fields=fields)


def check(line, target_reply, context=None, extras=None):
    parsed = assertions.parse(line)
    return assertions.evaluate(parsed, target_reply, context or Context(),
                               extras).ok


class ParseTests(unittest.TestCase):

    def test_target_operator_and_value(self):
        parsed = assertions.parse("status == NOERROR")
        self.assertEqual(parsed.target, "status")
        self.assertEqual(parsed.op, "==")
        self.assertEqual(parsed.value, "NOERROR")

    def test_value_keeps_its_spaces(self):
        # `replies == resourcerequest: ok` is one value, not two.
        parsed = assertions.parse("replies == resourcerequest: ok")
        self.assertEqual(parsed.value, "resourcerequest: ok")

    def test_nullary_operators_take_no_value(self):
        parsed = assertions.parse("error absent")
        self.assertIsNone(parsed.value)
        self.assertRaises(ConfigError, assertions.parse, "error absent junk")

    def test_unknown_operator_is_rejected(self):
        self.assertRaises(ConfigError, assertions.parse, "status eq NOERROR")

    def test_bad_regex_is_rejected_at_parse_time(self):
        self.assertRaises(ConfigError, assertions.parse, "text matches [")

    def test_block_skips_blanks_and_comments(self):
        block = "\n# a comment\nstatus == 200\n\nsize > 0\n"
        parsed = assertions.parse_block(block)
        self.assertEqual([item.target for item in parsed], ["status", "size"])


class ComparisonTests(unittest.TestCase):

    def test_equality_is_textual_by_default(self):
        self.assertTrue(check("status == NOERROR", reply(status="NOERROR")))
        self.assertFalse(check("status == NOERROR", reply(status="NXDOMAIN")))

    def test_equality_is_numeric_when_both_sides_are(self):
        # curl reports a status as an int and a .conf writes it as text.
        self.assertTrue(check("status == 200", reply(status=200)))
        self.assertTrue(check("status == 200", reply(status="200")))

    def test_equality_is_address_aware(self):
        self.assertTrue(check("data == 10.99.1.11", reply(data="10.99.1.11 ")))

    def test_a_list_means_any_of_these(self):
        # A name with two A records satisfies an assertion naming either.
        two = reply(data=["10.99.1.11", "10.99.1.12"])
        self.assertTrue(check("data == 10.99.1.12", two))

    def test_ordering_needs_numbers_on_both_sides(self):
        self.assertTrue(check("size > 0", reply(size=512)))
        self.assertFalse(check("size > 0", reply(size="not a number")))

    def test_membership_of_a_cidr(self):
        self.assertTrue(check("data in 10.99.1.0/24", reply(data="10.99.1.11")))
        self.assertFalse(check("data in 10.99.2.0/24", reply(data="10.99.1.11")))

    def test_membership_of_a_range(self):
        self.assertTrue(check("data in 10.99.1.1-10.99.1.20",
                              reply(data="10.99.1.11")))

    def test_membership_of_a_list(self):
        self.assertTrue(check("status in NOERROR, NXDOMAIN",
                              reply(status="NXDOMAIN")))

    def test_substring_operators(self):
        text = reply(text="linux /xcat/genesis.kernel destiny=install")
        self.assertTrue(check("text contains destiny=install", text))
        self.assertTrue(check("text starts-with linux", text))
        self.assertTrue(check("text ends-with destiny=install", text))

    def test_matches_is_multiline(self):
        text = reply(text="first line\nlinux /boot/vmlinuz\n")
        self.assertTrue(check(r"text matches ^linux\s+/boot", text))


class PresenceTests(unittest.TestCase):

    def test_present_and_absent(self):
        self.assertTrue(check("kernel present", reply(kernel="genesis.kernel")))
        self.assertFalse(check("kernel present", reply(kernel="")))
        self.assertTrue(check("error absent", reply(error="")))
        self.assertTrue(check("error absent", reply()))

    def test_an_empty_list_is_absence(self):
        self.assertTrue(check("callbacks absent", reply(callbacks=[])))
        self.assertFalse(check("callbacks present", reply(callbacks=[])))

    def test_a_positive_operator_fails_on_a_missing_field(self):
        self.assertFalse(check("bootfile == pxelinux.0", reply()))

    def test_a_negative_operator_holds_on_a_missing_field(self):
        # A reply naming no boot file has certainly not named the wrong one.
        self.assertTrue(check("bootfile != pxelinux.0", reply()))
        self.assertTrue(check("bootfile not-in a, b", reply()))


class IndexingTests(unittest.TestCase):

    def test_a_bare_list_name_is_its_first_element(self):
        self.assertTrue(check("lines == done", reply(lines=["done", "ready"])))

    def test_an_index_selects_an_element(self):
        self.assertTrue(check("lines.1 == ready", reply(lines=["done", "ready"])))

    def test_an_index_past_the_end_is_absence_not_an_error(self):
        self.assertFalse(check("lines.5 == ready", reply(lines=["done"])))

    def test_a_mapping_is_addressed_by_key(self):
        headers = reply(header={"content-type": "text/plain"})
        self.assertTrue(check("header.content-type == text/plain", headers))


class ReferenceTests(unittest.TestCase):

    def test_a_reference_resolves_against_an_earlier_reply(self):
        ctx = Context()
        ctx.bind("overtftp", reply(sha256="abc123"))
        self.assertTrue(check("sha256 == $overtftp.sha256",
                              reply(sha256="abc123"), ctx))
        self.assertFalse(check("sha256 == $overtftp.sha256",
                               reply(sha256="different"), ctx))

    def test_a_reference_to_a_step_that_has_not_run_is_an_error(self):
        parsed = assertions.parse("sha256 == $nosuchstep.sha256")
        self.assertRaises(ConfigError, assertions.evaluate, parsed,
                          reply(sha256="abc"), Context())


class MetaTargetTests(unittest.TestCase):

    def test_attempt_comes_from_the_runner_not_the_reply(self):
        self.assertTrue(check("attempt == 1", reply(), None, {"attempt": 1}))
        self.assertFalse(check("attempt == 1", reply()))


if __name__ == "__main__":
    unittest.main()
