import unittest

import helper                                    # noqa: F401

from dhcptest_lib import subst
from dhcptest_lib.errors import ConfigError
from dhcptest_lib.model import Reply


class References(unittest.TestCase):
    """Static analysis, the part `validate` leans on."""

    def test_finds_references(self):
        self.assertEqual(subst.references("$offer.address and $ack.server_id"),
                         [("offer", "address"), ("ack", "server_id")])

    def test_configparser_syntax_is_not_a_reference(self):
        # %(net)s is interpolated before a value ever reaches this module.
        self.assertEqual(subst.references("%(net)s"), [])

    def test_variables_reports_what_a_raw_file_still_needs(self):
        self.assertEqual(subst.variables("%(net)s and %(server)s"),
                         {"net", "server"})
        self.assertEqual(subst.variables("$offer.address"), set())

    def test_none_has_no_references(self):
        self.assertEqual(subst.references(None), [])
        self.assertEqual(subst.variables(None), set())

    def test_check_field_accepts_names_aliases_and_opt_numbers(self):
        self.assertTrue(subst.check_field("yiaddr"))
        self.assertTrue(subst.check_field("address"))       # alias
        self.assertTrue(subst.check_field("server_id"))     # option-backed
        self.assertTrue(subst.check_field("opt54"))
        self.assertTrue(subst.check_field("opt0x36"))

    def test_check_field_rejects_typos(self):
        self.assertFalse(subst.check_field("addres"))
        self.assertFalse(subst.check_field("optfifty"))
        self.assertFalse(subst.check_field("opt"))


class Resolution(unittest.TestCase):

    def setUp(self):
        self.context = subst.Context()
        self.context.bind("offer", Reply(
            msgtype="OFFER", yiaddr="10.0.0.101", file="xcat/xnba.kpxe",
            options={54: "10.0.0.1", 51: 43200, 55: [1, 3, 6]}))

    def test_a_reference_resolves_to_a_field_of_the_reply(self):
        self.assertEqual(subst.resolve("$offer.address", self.context),
                         "10.0.0.101")
        self.assertEqual(subst.resolve("$offer.server_id", self.context),
                         "10.0.0.1")

    def test_mixed_text_is_substituted_in_place(self):
        self.assertEqual(
            subst.resolve("host-$offer.address.local", self.context),
            "host-10.0.0.101.local")

    def test_configparser_syntax_is_left_alone(self):
        # It cannot appear here -- configparser already ate it -- but if it
        # does, passing it through beats mangling it.
        self.assertEqual(subst.resolve("%(net)s", self.context), "%(net)s")

    def test_unbound_reference_is_an_error(self):
        self.assertRaises(ConfigError, subst.resolve, "$ack.address",
                          self.context)

    def test_reference_to_a_missing_option_is_an_error(self):
        self.assertRaises(ConfigError, subst.resolve, "$offer.router",
                          self.context)

    def test_format_value_renders_lists_and_booleans(self):
        self.assertEqual(subst.format_value([1, 3, 6]), "1, 3, 6")
        self.assertEqual(subst.format_value(True), "yes")
        self.assertEqual(subst.format_value(43200), "43200")


if __name__ == "__main__":
    unittest.main()
