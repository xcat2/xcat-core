"""What `validate` catches offline: the DHCP state walk, fields, references."""

import unittest

import context

from blackboxtest_lib import config, validate


def problems(test, text):
    scenario, = config.load([context.write_conf(test, text)], raw=True)
    return validate.scenario_problems(scenario)


LEASE = """
[scenario lease]
description = discover then request
[step discover]
type = discover
[step request]
type = request
requested_address = $offer.address
server_id = $offer.server_id
assert =
    msgtype == ACK
[step fetch]
type = tftp
server = $lease.server_id
path = $discover.bootfile
assert =
    size > 0
    $request.address == $offer.address
"""


class DhcpWalk(unittest.TestCase):

    def test_a_clean_lease_then_a_fetch_has_no_problems(self):
        self.assertEqual(problems(self, LEASE), [])

    def test_a_request_without_a_discover_needs_a_requested_address(self):
        found = problems(self, "[scenario s]\n[step r]\ntype = request\n")
        self.assertTrue(any("needs requested_address=" in p for p in found), found)

    def test_a_renew_before_bound_is_illegal(self):
        found = problems(self, "[scenario s]\n[step r]\ntype = renew\n")
        self.assertTrue(any("not legal in state INIT" in p for p in found), found)

    def test_an_impossible_expectation_is_rejected(self):
        found = problems(self, "[scenario s]\n[step d]\ntype = discover\n"
                               "expect = ack\n")
        self.assertTrue(any("expect=ack is not a reply" in p for p in found))
        found = problems(self, "[scenario s]\n[step d]\ntype = tftp\n"
                               "server = x\npath = y\nexpect = offer\n")
        self.assertTrue(any("unknown expect=offer" in p for p in found))

    def test_expect_none_binds_nothing_and_leaves_the_state(self):
        found = problems(self, "[scenario s]\n[step d]\ntype = discover\n"
                               "expect = none\n[step r]\ntype = request\n"
                               "server_id = $offer.server_id\n")
        self.assertTrue(any("before anything binds $offer" in p for p in found))
        self.assertTrue(any("needs requested_address=" in p for p in found))

    def test_a_release_gives_the_lease_up(self):
        text = LEASE.replace("[step fetch]", "[step rel]\ntype = release\n"
                             "[step d2]\ntype = discover\n[step fetch]")
        self.assertEqual(problems(self, text), [])

    def test_an_alias_the_step_rebinds_is_not_an_earlier_reply(self):
        # A renew rebinds $lease to its own ACK before its assertions run, so
        # `yiaddr == $lease.address` compares the reply with itself.
        text = LEASE.replace("[step fetch]", """[step renew]
type = renew
server_id = $lease.server_id
assert =
    yiaddr == $lease.address
    yiaddr == $request.address
[step fetch]""")
        found = problems(self, text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("$lease is this step's own reply", found[0])

    def test_a_literal_mac_is_checked(self):
        found = problems(self, "[scenario s]\n[step d]\ntype = discover\n"
                               "mac = 02:00:zz:00:00:01\n")
        self.assertTrue(any("not a MAC" in p for p in found), found)


class Fields(unittest.TestCase):

    def test_a_field_the_step_type_cannot_carry(self):
        found = problems(self, "[scenario s]\n[step t]\ntype = tftp\n"
                               "server = x\npath = y\nassert =\n"
                               "    status == 200\n")
        self.assertTrue(any("tftp reply has no field 'status'" in p
                            for p in found), found)

    def test_a_reference_field_is_checked_against_the_step_it_names(self):
        found = problems(self, LEASE.replace("$discover.bootfile",
                                             "$discover.sha256"))
        self.assertTrue(any("discover reply has no field .sha256" in p
                            for p in found), found)

    def test_indexed_and_mapped_targets(self):
        text = ("[scenario s]\n[step h]\ntype = http\nurl = http://x/\n"
                "assert =\n    header.content-type == a\n    size > 0\n"
                "[step q]\ntype = dns\nserver = x\nname = y\nassert =\n"
                "    data.0 == 1.2.3.4\n    data.x == 1\n")
        found = problems(self, text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("data.x", found[0])

    def test_dhcp_targets_include_options_by_name_and_number(self):
        text = ("[scenario s]\n[step d]\ntype = discover\nassert =\n"
                "    option:54 present\n    router present\n    67 absent\n"
                "    offers == 1\n    nonsense present\n")
        found = problems(self, text)
        self.assertEqual(len(found), 1, found)
        self.assertIn("nonsense", found[0])


class References(unittest.TestCase):

    def test_a_forward_reference_is_rejected(self):
        found = problems(self, "[scenario s]\n[step a]\ntype = extract\n"
                               "from = $b.text\npattern = x\n"
                               "[step b]\ntype = noop\n")
        self.assertTrue(any("before anything binds $b" in p for p in found))

    def test_an_assertion_may_read_its_own_step(self):
        found = problems(self, "[scenario s]\n[step a]\ntype = extract\n"
                               "from = abc\npattern = (b)\nassert =\n"
                               "    $a.value == b\n")
        self.assertEqual(found, [])

    def test_required_keys_and_duplicate_names(self):
        found = problems(self, "[scenario s]\n[step a]\ntype = dns\n"
                               "server = x\n[step h]\ntype = http\n")
        self.assertTrue(any("needs name=" in p for p in found))
        self.assertTrue(any("url=, or server= and path=" in p for p in found))

    def test_required_variables(self):
        scenario, = config.load([context.write_conf(
            self, "[scenario s]\n[step a]\ntype = tftp\nserver = %(srv)s\n"
                  "path = x\nassert =\n    size > %(min)s\n")], raw=True)
        self.assertEqual(validate.required_variables([scenario]),
                         set(["srv", "min"]))


class ShippedFiles(unittest.TestCase):

    def test_every_shipped_scenario_validates(self):
        for scenario in config.load(context.conf_files(), raw=True):
            self.assertEqual(validate.scenario_problems(scenario), [])


if __name__ == "__main__":
    unittest.main()
