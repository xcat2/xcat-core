"""Loading .conf files: sections, defaults, variables, and what is refused."""

import unittest

import context

from blackboxtest_lib import config
from blackboxtest_lib.errors import ConfigError

MIXED = """
[vars]
server = 10.0.0.1

[defaults]
server  = %(server)s
bind    = 10.0.0.11
timeout = 3
client_arch = 0x0007

[scenario boot]
description = a DHCP step and a TFTP step share a file
interface   = eth9

[step discover]
type = discover
assert =
    msgtype == OFFER

[step fetch]
type = tftp
path = $discover.bootfile
retries = 5
assert =
    size > 0
"""


class Loading(unittest.TestCase):

    def load(self, text, overrides=None, raw=False):
        return config.load([context.write_conf(self, text)], overrides, raw)

    def test_sections_become_scenarios_and_steps(self):
        scenario, = self.load(MIXED)
        self.assertEqual(scenario.name, "boot")
        self.assertEqual(scenario.interface, "eth9")
        self.assertEqual([s.name for s in scenario.steps], ["discover", "fetch"])
        self.assertEqual(scenario.steps[0].assertions[0].render(),
                         "msgtype == OFFER")

    def test_a_default_reaches_only_the_steps_that_take_it(self):
        discover, fetch = self.load(MIXED)[0].steps
        self.assertEqual(fetch.param("server"), "10.0.0.1")
        self.assertEqual(fetch.param("bind"), "10.0.0.11")
        self.assertNotIn("server", discover.params)
        self.assertEqual(discover.param("client_arch"), "0x0007")
        self.assertNotIn("client_arch", fetch.params)

    def test_timeouts_and_retries_default_per_family(self):
        discover, fetch = self.load(MIXED)[0].steps
        self.assertEqual((discover.timeout, discover.retries), (3.0, 3))
        self.assertEqual((fetch.timeout, fetch.retries), (3.0, 5))
        scenario, = self.load("[scenario s]\n[step n]\ntype = noop\n")
        self.assertEqual((scenario.steps[0].timeout, scenario.steps[0].retries),
                         (5.0, 2))

    def test_a_command_line_value_beats_vars(self):
        fetch = self.load(MIXED, {"server": "10.0.0.2"})[0].steps[1]
        self.assertEqual(fetch.param("server"), "10.0.0.2")

    def test_a_variable_never_becomes_a_step_key(self):
        fetch = self.load(MIXED, {"path": "/etc/passwd"})[0].steps[1]
        self.assertEqual(fetch.param("path"), "$discover.bootfile")

    def test_an_undefined_variable_names_the_flag_that_fixes_it(self):
        with self.assertRaisesRegex(ConfigError, r"pass --set net=<value>"):
            self.load("[scenario s]\n[step n]\ntype = noop\n"
                      "assert =\n    $n.x in %(net)s\n")

    def test_raw_loading_leaves_variables_in_place(self):
        scenario, = self.load("[scenario s]\n[step t]\ntype = tftp\n"
                              "server = %(server)s\npath = x\n", raw=True)
        self.assertEqual(scenario.steps[0].param("server"), "%(server)s")

    def test_a_semicolon_starts_an_inline_comment(self):
        scenario, = self.load("[scenario s]\n[step t]\ntype = tftp\n"
                              "server = 10.0.0.1 ; the MN\npath = x\n")
        self.assertEqual(scenario.steps[0].param("server"), "10.0.0.1")

    def test_what_is_refused(self):
        cases = {
            "unknown key": "[scenario s]\n[step t]\ntype = tftp\nbogus = 1\n",
            "DHCP key on a tftp step": "[scenario s]\n[step t]\ntype = tftp\n"
                                       "client_arch = 7\n",
            "no type": "[scenario s]\n[step t]\npath = x\n",
            "unknown type": "[scenario s]\n[step t]\ntype = gopher\n",
            "step before scenario": "[step t]\ntype = noop\n",
            "scenario without steps": "[scenario s]\n",
            "unknown section": "[scenario s]\n[step t]\ntype = noop\n[bogus]\n",
            "type as a default": "[defaults]\ntype = noop\n[scenario s]\n"
                                 "[step t]\ntype = noop\n",
            "a repeated section": "[scenario s]\n[step t]\ntype = noop\n"
                                  "[step t]\ntype = noop\n",
            "bad timeout": "[scenario s]\n[step t]\ntype = noop\ntimeout = soon\n",
            "bad operator": "[scenario s]\n[step t]\ntype = noop\n"
                            "assert =\n    x ~= y\n",
            "bad regex": "[scenario s]\n[step t]\ntype = noop\n"
                         "assert =\n    x matches (\n",
            "nothing": "# empty\n",
        }
        for why, text in cases.items():
            with self.assertRaises(ConfigError, msg=why):
                self.load(text)

    def test_a_scenario_name_may_not_be_reused_across_files(self):
        text = "[scenario s]\n[step t]\ntype = noop\n"
        paths = [context.write_conf(self, text, "a.conf"),
                 context.write_conf(self, text, "b.conf")]
        self.assertRaisesRegex(ConfigError, "defined in both",
                               config.load, paths)

    def test_a_missing_file_names_itself(self):
        self.assertRaisesRegex(ConfigError, "/no/such.conf: no such file",
                               config.load, ["/no/such.conf"])


class ShippedFiles(unittest.TestCase):

    def test_every_shipped_scenario_has_a_description_and_a_check(self):
        # A scenario with no assertion and no stated expectation produces no
        # test point, and passes whatever the server does.
        for scenario in config.load(context.conf_files(), raw=True):
            self.assertTrue(scenario.description, scenario.name)
            self.assertTrue(any(s.assertions or s.expect for s in scenario.steps),
                            scenario.name)


if __name__ == "__main__":
    unittest.main()
