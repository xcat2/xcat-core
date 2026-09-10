import os
import unittest

import helper

from dhcptest_lib import config, machine
from dhcptest_lib.model import Scenario, Step


def step(name, type, expect=None, params=None, assertions=()):
    return Step(name=name, type=type, expect=expect, params=params or {},
                assertions=assertions)


def scenario(*steps):
    return Scenario(name="s", steps=steps)


class Table(unittest.TestCase):

    def test_known_step_types_covers_passive_and_protocol_types(self):
        types = machine.known_step_types()
        for expected in ("discover", "request", "renew", "rebind", "release",
                         "decline", "inform", "noop", "sleep"):
            self.assertIn(expected, types)

    def test_inform_is_legal_from_any_state(self):
        self.assertIsNotNone(machine.transition_for(machine.INIT, "inform"))
        self.assertIsNotNone(machine.transition_for(machine.BOUND, "inform"))

    def test_discover_is_not_legal_once_bound(self):
        self.assertIsNone(machine.transition_for(machine.BOUND, "discover"))

    def test_a_selecting_request_expects_ack_or_nak(self):
        transition = machine.transition_for(machine.SELECTING, "request")
        self.assertEqual(transition.expects, frozenset(["ack", "nak"]))
        self.assertEqual(transition.default_expect, "ack")
        self.assertEqual(transition.next_state, machine.BOUND)

    def test_renew_is_unicast_and_rebind_is_not(self):
        self.assertTrue(machine.transition_for(machine.BOUND, "renew").unicast)
        self.assertFalse(machine.transition_for(machine.BOUND, "rebind").unicast)


class Validation(unittest.TestCase):

    def test_a_clean_lease_scenario_has_no_problems(self):
        self.assertEqual(machine.validate_scenario(scenario(
            step("d", "discover"),
            step("r", "request", params={"requested_address": "$offer.address",
                                         "server_id": "$offer.server_id"}),
        )), [])

    def test_a_request_without_a_discover_is_rejected(self):
        problems = machine.validate_scenario(scenario(step("r", "request")))
        self.assertEqual(len(problems), 1)
        self.assertIn("needs requested_address=", problems[0])

    def test_a_renew_before_bound_is_rejected(self):
        problems = machine.validate_scenario(scenario(step("x", "renew")))
        self.assertIn("not legal in state INIT", problems[0])

    def test_a_reference_to_a_later_step_is_rejected(self):
        problems = machine.validate_scenario(scenario(
            step("d", "discover", params={"ciaddr": "$ack.address"}),
        ))
        self.assertIn("used before anything binds $ack", problems[0])

    def test_a_misspelt_reply_field_is_rejected(self):
        problems = machine.validate_scenario(scenario(
            step("d", "discover"),
            step("r", "request", params={"requested_address": "$offer.addres"}),
        ))
        self.assertIn("not a field of a DHCP reply", problems[0])

    def test_an_impossible_expectation_is_rejected(self):
        problems = machine.validate_scenario(scenario(
            step("d", "discover", expect="ack"),
        ))
        self.assertIn("is not a possible reply", problems[0])

    def test_expect_none_leaves_the_state_alone_and_binds_nothing(self):
        problems = machine.validate_scenario(scenario(
            step("silent", "discover", expect="none"),
            step("again", "discover"),
        ))
        self.assertEqual(problems, [])

    def test_a_duplicate_step_name_is_rejected(self):
        problems = machine.validate_scenario(scenario(
            step("d", "discover"), step("d", "discover", expect="none"),
        ))
        self.assertIn("duplicate step name", problems[0])

    def test_expected_types_follows_expect(self):
        self.assertEqual(
            machine.expected_types(step("d", "discover"), machine.INIT),
            frozenset(["offer"]))
        self.assertEqual(
            machine.expected_types(step("d", "discover", expect="none"),
                                   machine.INIT),
            frozenset())
        self.assertEqual(
            machine.expected_types(step("r", "request", expect="any"),
                                   machine.SELECTING),
            frozenset(["ack", "nak"]))

    def test_required_variables_gathers_every_set_name(self):
        names = machine.required_variables([scenario(
            step("d", "discover", params={"mac": "%(who)s"},
                 assertions=(),),
        )])
        self.assertEqual(names, {"who"})


class ShippedFiles(unittest.TestCase):
    """conf/ must stay valid: this is what `dhcptest validate` runs in CI."""

    def test_every_shipped_scenario_validates(self):
        for name in sorted(os.listdir(helper.CONF)):
            if not name.endswith(".conf"):
                continue
            scenarios, _ = config.load([os.path.join(helper.CONF, name)],
                                       raw=True)
            for one in scenarios:
                problems = machine.validate_scenario(one)
                self.assertEqual(problems, [],
                                 "%s/%s: %s" % (name, one.name, problems))


if __name__ == "__main__":
    unittest.main()
