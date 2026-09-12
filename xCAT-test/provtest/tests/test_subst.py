"""`$step.field`: the references that make a scenario a chain.

A cross-stage scenario fetches a config, reads a name out of it, and fetches
that name. The reference is what carries the second half, so it is resolved at
run time and not by configparser -- and the two syntaxes have to share a file
without escaping each other.
"""

import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import subst
from provtest_lib.errors import ConfigError
from provtest_lib.model import Reply


def reply(**fields):
    return Reply(kind="test", fields=fields)


class ScanningTests(unittest.TestCase):

    def test_references_are_found(self):
        found = subst.references("http://%(server)s:$configport.value/x")
        self.assertEqual(found, [("configport", "value")])

    def test_a_trailing_dot_is_not_part_of_the_field(self):
        self.assertEqual(subst.references("$config.text."), [("config", "text")])

    def test_an_indexed_field_is_one_reference(self):
        self.assertEqual(subst.references("$mon.lines.0"), [("mon", "lines.0")])

    def test_variables_are_found_separately(self):
        self.assertEqual(subst.variables("%(server)s and %(client)s"),
                         set(["server", "client"]))

    def test_the_two_syntaxes_do_not_see_each_other(self):
        text = "%(server)s/$config.text"
        self.assertEqual(subst.variables(text), set(["server"]))
        self.assertEqual(subst.references(text), [("config", "text")])

    def test_nothing_to_find_is_not_an_error(self):
        self.assertEqual(subst.references(None), [])
        self.assertEqual(subst.variables(None), set())


class ResolutionTests(unittest.TestCase):

    def setUp(self):
        self.ctx = subst.Context()
        self.ctx.bind("config", reply(text="linux /xcat/vmlinuz\n",
                                      sha256="abc123"))

    def test_a_reference_is_replaced_by_the_field(self):
        self.assertEqual(subst.resolve("$config.sha256", self.ctx), "abc123")

    def test_a_reference_is_replaced_inside_a_larger_string(self):
        self.assertEqual(subst.resolve("sha=$config.sha256!", self.ctx),
                         "sha=abc123!")

    def test_an_unbound_step_says_it_has_not_run(self):
        try:
            subst.resolve("$later.value", self.ctx)
        except ConfigError as exc:
            self.assertIn("no step of that name has run yet", str(exc))
        else:
            self.fail("a forward reference resolved")

    def test_a_field_the_reply_does_not_carry_is_an_error(self):
        self.assertRaises(ConfigError, subst.resolve, "$config.kernel", self.ctx)

    def test_rebinding_a_name_keeps_one_entry(self):
        self.ctx.bind("config", reply(sha256="second"))
        self.assertEqual(self.ctx.order.count("config"), 1)
        self.assertEqual(subst.resolve("$config.sha256", self.ctx), "second")


class FormattingTests(unittest.TestCase):
    """How a resolved value is rendered: the way a .conf author would type it."""

    def test_a_boolean_is_yes_or_no(self):
        self.assertEqual(subst.format_value(True), "yes")
        self.assertEqual(subst.format_value(False), "no")

    def test_bytes_are_decoded(self):
        self.assertEqual(subst.format_value(b"ready"), "ready")

    def test_a_list_is_joined(self):
        self.assertEqual(subst.format_value(["a", "b"]), "a, b")

    def test_a_mapping_is_sorted_and_joined(self):
        self.assertEqual(subst.format_value({"b": 2, "a": 1}), "a=1, b=2")

    def test_a_reference_to_a_list_gives_its_first_element(self):
        ctx = subst.Context()
        ctx.bind("dns", reply(data=["10.99.1.11", "10.99.1.12"]))
        self.assertEqual(subst.resolve("$dns.data", ctx), "10.99.1.11")


if __name__ == "__main__":
    unittest.main()
