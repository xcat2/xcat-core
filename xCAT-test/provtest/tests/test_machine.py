"""The offline half: what a step of each type may say, and what it returns.

`validate` runs this in a checkout with no network and no root, which is where
a misspelt reply field or a reference to a step that has not run yet should be
caught -- long before a management node is involved.
"""

import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import machine
from provtest_lib.assertions import parse_block
from provtest_lib.errors import ConfigError
from provtest_lib.model import Scenario, Step


def step(name, type, assertions="", **params):
    return Step(name=name, type=type, expect=params.pop("expect", None),
                params=params, assertions=parse_block(assertions),
                source="test")


def scenario(*steps):
    return Scenario(name="case", description="d", steps=steps, source="test")


def problems(*steps):
    return machine.validate_scenario(scenario(*steps))


class TypeTests(unittest.TestCase):

    def test_every_shipped_type_is_declared_everywhere(self):
        # A type with no key table or no reply table would validate nothing.
        for name in machine.known_step_types():
            self.assertIn(name, machine.STEP_KEYS)
            self.assertIn(name, machine.REPLY_FIELDS)
            self.assertIn(name, machine.REQUIRED_KEYS)

    def test_an_unknown_type_is_rejected(self):
        self.assertRaises(ConfigError, machine.check_type, "smtp")

    def test_bind_is_available_to_every_type(self):
        # xcatd names a client by the reverse lookup of the address a request
        # arrived from, so no step type may be unable to choose one.
        for name in machine.known_step_types():
            self.assertIn("bind", machine.allowed_keys(name))


class RequiredKeyTests(unittest.TestCase):

    def test_a_dns_step_needs_a_name(self):
        found = problems(step("q", "dns", server="10.99.1.1"))
        self.assertTrue(any("needs name=" in text for text in found), found)

    def test_a_tftp_step_needs_a_path(self):
        found = problems(step("f", "tftp", server="10.99.1.1"))
        self.assertTrue(any("needs path=" in text for text in found), found)

    def test_an_http_step_needs_a_url_or_a_server_and_path(self):
        self.assertTrue(problems(step("g", "http")))
        self.assertFalse(problems(step("g", "http", url="http://h/x")))
        self.assertFalse(problems(step("g", "http", server="h", path="/x")))

    def test_an_xcatreq_step_needs_a_command(self):
        found = problems(step("r", "xcatreq", server="10.99.1.1"))
        self.assertTrue(any("needs command=" in text for text in found), found)

    def test_an_extract_step_needs_a_source_and_a_pattern(self):
        self.assertTrue(problems(step("e", "extract", pattern="(x)")))
        self.assertTrue(problems(step("e", "extract", **{"from": "$a.text"})))

    def test_an_extract_group_must_be_a_number(self):
        found = problems(step("e", "extract", pattern="(x)", group="first",
                              **{"from": "$a.text"}))
        self.assertTrue(any("group= must be a number" in t for t in found), found)


class ExpectationTests(unittest.TestCase):

    def test_the_three_expectations_are_accepted(self):
        for value in ("ok", "fail", "any"):
            self.assertFalse(problems(
                step("s", "tftp", server="h", path="p", expect=value)))

    def test_an_unknown_expectation_is_rejected(self):
        found = problems(step("s", "tftp", server="h", path="p", expect="maybe"))
        self.assertTrue(any("unknown expect=" in text for text in found), found)


class AssertionTargetTests(unittest.TestCase):

    def test_a_field_the_type_produces_is_accepted(self):
        self.assertFalse(problems(
            step("f", "tftp", "size > 0\nsha256 present", server="h", path="p")))

    def test_a_field_of_another_type_is_rejected(self):
        # `status` belongs to dns and http; a tftp reply has no such field, and
        # an assertion naming it would silently never hold.
        found = problems(step("f", "tftp", "status == 200", server="h", path="p"))
        self.assertTrue(any("has no field" in text for text in found), found)

    def test_a_mapping_target_is_accepted_by_key(self):
        self.assertFalse(problems(
            step("g", "http", "header.content-type == text/plain",
                 url="http://h/x")))

    def test_a_mapping_target_of_the_wrong_type_is_rejected(self):
        found = problems(step("f", "tftp", "header.x == y", server="h", path="p"))
        self.assertTrue(any("carries no header" in text for text in found), found)

    def test_an_indexed_list_target_is_accepted(self):
        self.assertFalse(problems(
            step("m", "monitor", "lines.0 == done", server="h", send="x")))


class ReferenceTests(unittest.TestCase):

    def test_a_reference_backwards_is_accepted(self):
        self.assertFalse(problems(
            step("config", "tftp", "size > 0", server="h", path="p"),
            step("kernel", "extract", "matched == yes",
                 pattern="(x)", **{"from": "$config.text"})))

    def test_a_reference_forwards_is_rejected(self):
        found = problems(
            step("kernel", "extract", "matched == yes",
                 pattern="(x)", **{"from": "$config.text"}),
            step("config", "tftp", "size > 0", server="h", path="p"))
        self.assertTrue(any("has not run yet" in text for text in found), found)

    def test_a_reference_to_no_known_field_is_rejected(self):
        found = problems(
            step("config", "tftp", "size > 0", server="h", path="p"),
            step("kernel", "tftp", "size > 0", server="h",
                 path="$config.nosuchfield"))
        self.assertTrue(any("no reply field" in text for text in found), found)

    def test_a_reference_in_an_assertion_value_is_checked_too(self):
        found = problems(
            step("a", "http", "status == 200", url="http://h/x"),
            step("b", "http", "sha256 == $a.nosuchfield", url="http://h/y"))
        self.assertTrue(any("no reply field" in text for text in found), found)

    def test_a_step_defined_twice_is_reported(self):
        found = problems(step("f", "noop"), step("f", "noop"))
        self.assertTrue(any("defined twice" in text for text in found), found)


class RequiredVariableTests(unittest.TestCase):

    def test_variables_are_collected_from_keys_and_assertions(self):
        found = machine.required_variables([scenario(
            step("f", "tftp", "text contains %(node)s",
                 server="%(server)s", path="%(knownfile)s"))])
        self.assertEqual(found, set(["server", "knownfile", "node"]))

    def test_every_shipped_file_declares_what_it_needs(self):
        # `validate` prints this list, and the fixture passes exactly it; a
        # variable nobody supplies is a run that stops before its first socket.
        from provtest_lib import config

        scenarios, _ = config.load(context.conf_files(), {}, raw=True)
        needed = machine.required_variables(scenarios)
        self.assertIn("server", needed)
        self.assertIn("client", needed)
        for name in needed:
            self.assertRegex(name, r"^[a-z][a-z0-9_]*$")


if __name__ == "__main__":
    unittest.main()
