"""Reading .conf files: sections, defaults, variables, and what is rejected.

Every scenario in this suite is data, so a mistake in a file has to fail loudly
at load time. Silence would mean a step that never ran counted as a pass.
"""

import os
import shutil
import tempfile
import unittest

import context                                   # noqa: F401  (sys.path)

from provtest_lib import config
from provtest_lib.errors import ConfigError


BASIC = """
[vars]
domain = provtest.cluster

[defaults]
server  = 10.99.1.1
timeout = 8

[scenario node-reverse]
description = The node's address resolves to its name

[step ptr]
type   = dns
name   = 11.1.99.10.in-addr.arpa
rrtype = PTR
assert =
    status == NOERROR
    data   contains provtestcn.%(domain)s
"""


class Harness(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="provtest-config-")
        self.addCleanup(shutil.rmtree, self.dir, True)

    def write(self, text, name="case.conf"):
        path = os.path.join(self.dir, name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def load(self, text, overrides=None, raw=False, name="case.conf"):
        return config.load([self.write(text, name)], overrides or {}, raw)


class StructureTests(Harness):

    def test_a_file_loads_into_scenarios_and_steps(self):
        scenarios, variables = self.load(BASIC)
        self.assertEqual(len(scenarios), 1)
        scenario = scenarios[0]
        self.assertEqual(scenario.name, "node-reverse")
        self.assertEqual([step.name for step in scenario.steps], ["ptr"])
        self.assertEqual(variables["domain"], "provtest.cluster")

    def test_defaults_reach_a_step_that_does_not_set_them(self):
        scenario = self.load(BASIC)[0][0]
        self.assertEqual(scenario.steps[0].param("server"), "10.99.1.1")
        self.assertEqual(scenario.steps[0].timeout, 8.0)

    def test_a_step_overrides_a_default(self):
        text = BASIC.replace("rrtype = PTR", "rrtype = PTR\nserver = 10.99.1.9")
        scenario = self.load(text)[0][0]
        self.assertEqual(scenario.steps[0].param("server"), "10.99.1.9")

    def test_a_default_a_step_type_cannot_use_is_dropped_quietly(self):
        # One [defaults] serves dns, tftp and http steps in the same file, so
        # `path =` there must not make the dns step illegal.
        text = BASIC.replace("timeout = 8", "timeout = 8\npath = /install/x")
        scenario = self.load(text)[0][0]
        self.assertIsNone(scenario.steps[0].param("path"))

    def test_steps_keep_their_file_order(self):
        text = BASIC + "\n[step second]\ntype = noop\n\n[step third]\ntype = noop\n"
        scenario = self.load(text)[0][0]
        self.assertEqual([step.name for step in scenario.steps],
                         ["ptr", "second", "third"])

    def test_assertions_are_parsed_into_the_step(self):
        scenario = self.load(BASIC)[0][0]
        targets = [item.target for item in scenario.steps[0].assertions]
        self.assertEqual(targets, ["status", "data"])


class VariableTests(Harness):

    def test_a_variable_is_interpolated_from_vars(self):
        scenario = self.load(BASIC)[0][0]
        value = scenario.steps[0].assertions[1].value
        self.assertEqual(value, "provtestcn.provtest.cluster")

    def test_an_override_beats_vars(self):
        scenario = self.load(BASIC, {"domain": "other.cluster"})[0][0]
        self.assertEqual(scenario.steps[0].assertions[1].value,
                         "provtestcn.other.cluster")

    def test_an_undefined_variable_names_the_set_that_would_fix_it(self):
        text = BASIC.replace("%(domain)s", "%(nosuchvar)s")
        try:
            self.load(text)
        except ConfigError as exc:
            self.assertIn("--set nosuchvar=", str(exc))
        else:
            self.fail("an undefined variable was accepted")

    def test_raw_leaves_variables_alone(self):
        # `validate` runs in a checkout where no value has been supplied yet.
        scenario = self.load(BASIC, raw=True)[0][0]
        self.assertIn("%(domain)s", scenario.steps[0].assertions[1].value)

    def test_a_variable_never_becomes_a_step_key(self):
        # --set path=/install must not silently become every step's path=.
        scenario = self.load(BASIC, {"path": "/install"})[0][0]
        self.assertIsNone(scenario.steps[0].param("path"))

    def test_a_dollar_reference_survives_untouched(self):
        text = BASIC + "\n[step after]\ntype = extract\nfrom = $ptr.data\npattern = (.*)\n"
        scenario = self.load(text)[0][0]
        self.assertEqual(scenario.steps[1].param("from"), "$ptr.data")


class RejectionTests(Harness):

    def test_an_unknown_step_key_is_rejected(self):
        text = BASIC.replace("rrtype = PTR", "rrtype = PTR\nnosuchkey = 1")
        self.assertRaises(ConfigError, self.load, text)

    def test_an_unknown_step_type_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("type   = dns", "type   = smtp"))

    def test_a_step_with_no_type_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("type   = dns\n", ""))

    def test_a_step_before_any_scenario_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          "[step orphan]\ntype = noop\n")

    def test_a_scenario_with_no_steps_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          "[scenario empty]\ndescription = nothing\n")

    def test_an_unknown_section_is_rejected(self):
        self.assertRaises(ConfigError, self.load, BASIC + "\n[nonsense]\nx = 1\n")

    def test_type_may_not_be_a_default(self):
        # A default type would turn a misspelt type= into another protocol.
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("[defaults]", "[defaults]\ntype = dns"))

    def test_a_repeated_step_name_in_one_file_is_rejected(self):
        # configparser's own rule, and the reason step names are unique per
        # file rather than per scenario.
        self.assertRaises(ConfigError, self.load,
                          BASIC + "\n[scenario other]\n\n[step ptr]\ntype = noop\n")

    def test_a_scenario_defined_in_two_files_is_rejected(self):
        first = self.write(BASIC, "first.conf")
        second = self.write(BASIC, "second.conf")
        self.assertRaises(ConfigError, config.load, [first, second], {}, True)

    def test_a_missing_file_says_so(self):
        self.assertRaises(ConfigError, config.load,
                          [os.path.join(self.dir, "absent.conf")], {}, True)

    def test_a_non_numeric_timeout_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("timeout = 8", "timeout = soon"))


class ShippedFileTests(unittest.TestCase):
    """The files this suite ships must load and validate as they stand."""

    def test_every_shipped_file_parses(self):
        from provtest_lib import machine

        paths = context.conf_files()
        self.assertTrue(paths, "no .conf files are shipped")
        scenarios, _ = config.load(paths, {}, raw=True)
        problems = []
        for scenario in scenarios:
            problems.extend(machine.validate_scenario(scenario))
        self.assertEqual(problems, [])

    def test_every_shipped_scenario_has_a_description_and_an_assertion(self):
        scenarios, _ = config.load(context.conf_files(), {}, raw=True)
        for scenario in scenarios:
            self.assertTrue(scenario.description,
                            "%s has no description" % (scenario.name,))
            asserted = any(step.assertions for step in scenario.steps)
            self.assertTrue(asserted,
                            "%s asserts nothing at all" % (scenario.name,))


if __name__ == "__main__":
    unittest.main()
