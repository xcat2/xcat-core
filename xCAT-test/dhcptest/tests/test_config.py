import os
import tempfile
import unittest

import helper

from dhcptest_lib import config
from dhcptest_lib.errors import ConfigError

BASIC = """
[vars]
net = 10.0.0.0/24

[defaults]
interface = eth0
retries   = 2

[scenario basic]
description = one discover

[step d]
type   = discover
expect = offer
assert =
    msgtype == OFFER
    yiaddr  in %(net)s
"""


class Loading(unittest.TestCase):

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="dhcptest-")

    def write(self, text, name="t.conf"):
        path = os.path.join(self.dir, name)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def load(self, text, **kwargs):
        return config.load([self.write(text)], **kwargs)

    def test_sections_become_scenarios_steps_and_vars(self):
        scenarios, variables = self.load(BASIC)
        self.assertEqual(len(scenarios), 1)
        self.assertEqual(variables["net"], "10.0.0.0/24")
        scenario = scenarios[0]
        self.assertEqual(scenario.name, "basic")
        self.assertEqual(scenario.interface, "eth0")
        self.assertEqual(len(scenario.steps), 1)
        self.assertEqual(len(scenario.step("d").assertions), 2)

    def test_defaults_apply_and_a_step_overrides_them(self):
        scenarios, _ = self.load(BASIC)
        self.assertEqual(scenarios[0].step("d").retries, 2)
        scenarios, _ = self.load(BASIC.replace(
            "type   = discover", "type   = discover\nretries = 7"))
        self.assertEqual(scenarios[0].step("d").retries, 7)

    def test_command_line_beats_the_file(self):
        scenarios, variables = self.load(
            BASIC, overrides={"net": "192.168.0.0/24"}, interface="eth9")
        self.assertEqual(variables["net"], "192.168.0.0/24")
        self.assertEqual(scenarios[0].interface, "eth9")

    def test_a_literal_mac_is_checked_at_load_time(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("expect = offer",
                                        "expect = offer\nmac = nonsense"))

    def test_a_mac_carrying_a_reference_is_left_for_runtime(self):
        # $offer.chaddr is a reply that has not arrived yet, so it cannot be
        # checked as a MAC until the step runs.
        scenarios, _ = self.load(BASIC.replace(
            "expect = offer", "expect = offer\nmac = $offer.chaddr"))
        self.assertEqual(scenarios[0].step("d").param("mac"), "$offer.chaddr")

    def test_a_variable_is_interpolated_by_configparser(self):
        scenarios, _ = self.load(BASIC.replace(
            "net = 10.0.0.0/24", "net = 10.0.0.0/24\nwho = 02:00:de:ad:be:ef")
            .replace("expect = offer", "expect = offer\nmac = %(who)s"))
        self.assertEqual(scenarios[0].step("d").param("mac"),
                         "02:00:de:ad:be:ef")
        self.assertEqual(scenarios[0].step("d").assertions[1].value,
                         "10.0.0.0/24")

    def test_a_variable_may_share_a_name_with_a_step_key(self):
        # A variable is only ever read through %(...)s. Letting the two share a
        # namespace made `--set user_class=xNBA` delete the step's user_class.
        scenarios, _ = self.load(
            BASIC.replace("expect = offer",
                          "expect = offer\nuser_class = %(user_class)s"),
            overrides={"net": "10.0.0.0/24", "user_class": "xNBA"})
        self.assertEqual(scenarios[0].step("d").param("user_class"), "xNBA")

    def test_an_undefined_variable_names_the_flag_that_fixes_it(self):
        with self.assertRaises(ConfigError) as caught:
            self.load(BASIC.replace("%(net)s", "%(nowhere)s"))
        self.assertIn("--set nowhere=", str(caught.exception))

    def test_raw_loading_leaves_the_variables_in_place(self):
        # What `validate` and `list` do: check the shape of a file that has
        # not been given its values yet.
        scenarios, _ = self.load(BASIC.replace("%(net)s", "%(nowhere)s"),
                                 raw=True)
        self.assertEqual(scenarios[0].step("d").assertions[1].value,
                         "%(nowhere)s")

    def test_unknown_keys_and_sections_are_hard_errors(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("expect = offer", "expct = offer"))
        self.assertRaises(ConfigError, self.load, BASIC + "\n[nonsense]\na = b\n")

    def test_a_step_needs_a_type_and_a_scenario(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("type   = discover", "timeout = 1"))
        self.assertRaises(ConfigError, self.load,
                          "[step orphan]\ntype = discover\n")

    def test_an_unknown_step_type_is_rejected(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("type   = discover", "type = telepathy"))

    def test_a_scenario_needs_steps_and_a_file_needs_a_scenario(self):
        self.assertRaises(ConfigError, self.load, "[scenario empty]\n")
        self.assertRaises(ConfigError, self.load, "[vars]\na = b\n")

    def test_a_scenario_name_may_not_be_reused_across_files(self):
        first = self.write(BASIC, "a.conf")
        second = self.write(BASIC, "b.conf")
        self.assertRaises(ConfigError, config.load, [first, second])

    def test_a_missing_file_names_itself(self):
        with self.assertRaises(ConfigError) as caught:
            config.load([os.path.join(self.dir, "absent.conf")])
        self.assertIn("absent.conf", str(caught.exception))

    def test_numbers_must_be_numbers(self):
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("retries   = 2", "retries = soon"))
        self.assertRaises(ConfigError, self.load,
                          BASIC.replace("retries   = 2", "timeout = soon"))

    def test_a_semicolon_starts_an_inline_comment(self):
        scenarios, _ = self.load(
            BASIC.replace("type   = discover", "type   = discover ; the only one"))
        self.assertEqual(scenarios[0].step("d").type, "discover")


class ShippedFiles(unittest.TestCase):
    """Every .conf in conf/ must load and be internally consistent."""

    def test_all_shipped_conf_files_load(self):
        # raw=True is what `validate` does: a shipped file states which
        # variables it needs, and only a run supplies them.
        names = sorted(n for n in os.listdir(helper.CONF) if n.endswith(".conf"))
        self.assertTrue(names, "conf/ has no .conf files")
        for name in names:
            scenarios, _ = config.load([os.path.join(helper.CONF, name)],
                                       raw=True)
            self.assertTrue(scenarios, "%s defines no scenario" % (name,))


if __name__ == "__main__":
    unittest.main()
