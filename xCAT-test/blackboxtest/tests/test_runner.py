"""The runner, end to end, on steps that need no network."""

import io
import unittest

import context

from blackboxtest_lib import config, report, runner


def run(test, text, **options):
    scenarios = config.load([context.write_conf(test, text)])
    stream = io.StringIO()
    code = runner.run(scenarios, report.TapReporter(stream),
                      runner.RunOptions(**options))
    return stream.getvalue(), code


class LocalSteps(unittest.TestCase):

    def test_a_chain_resolves_references_between_steps(self):
        text, code = run(self, """
[scenario chain]
description = extract reads what an earlier step returned
[step config]
type = extract
from = linux /tftpboot/xcat/k initrd=/i
pattern = ^linux\\s+/?(?:tftpboot/)?(\\S+)
expect = ok
[step again]
type = extract
from = path=$config.value
pattern = path=(.*)
assert =
    value == xcat/k
    $config.matched == yes
""")
        self.assertEqual(code, 0, text)
        self.assertIn("ok 1 - chain/config: expect ok", text)
        self.assertIn("ok 2 - chain/again: value == xcat/k", text)

    def test_an_expectation_is_a_test_point_of_its_own(self):
        text, code = run(self, """
[scenario s]
description = nothing matches
[step miss]
type = extract
from = abc
pattern = z
expect = ok
""")
        self.assertEqual(code, 1)
        self.assertIn("not ok 1 - s/miss: expect ok", text)
        self.assertIn("'z' matched nothing", text)

    def test_a_step_that_cannot_run_fails_and_stops_its_scenario(self):
        text, code = run(self, """
[scenario s]
description = a reference to a field the reply lacks
[step a]
type = noop
[step b]
type = extract
from = $a.value
pattern = x
[step c]
type = noop
assert =
    $a.x absent
""")
        self.assertEqual(code, 1)
        self.assertIn("not ok 1 - s/b: step could not be run", text)
        self.assertNotIn("s/c", text)

    def test_a_dhcp_scenario_without_an_interface_is_skipped(self):
        # dhcp.require() refuses a host without scapy or root before any of
        # this runs, so stand it down to reach the per-scenario check.
        original = runner.dhcp.require
        runner.dhcp.require = lambda: None
        self.addCleanup(setattr, runner.dhcp, "require", original)
        text, code = run(self, """
[scenario d]
description = no NIC on this host
interface = nosuchnic0
[step discover]
type = discover
assert =
    msgtype == OFFER
""")
        self.assertEqual(code, 0)
        self.assertIn("# SKIP no such interface: nosuchnic0", text)



class DhcpExpectations(unittest.TestCase):
    """A DHCP step's expectation is a test point, as a service step's is."""

    CONF = """
[scenario noip]
description = S-07: a port marked *NOIP* is not answered
interface = lo
[step discover]
type = discover
expect = none
retries = 1
timeout = 0.1
"""

    def run_against(self, *answers):
        from blackboxtest_lib import dhcp
        from test_dhcp import FakeWire

        for name, value in (("require", lambda: None),
                            ("Wire", lambda interface: FakeWire(*answers)),
                            ("build_frame", lambda *args: None)):
            self.addCleanup(setattr, dhcp, name, getattr(dhcp, name))
            setattr(dhcp, name, value)
        return run(self, self.CONF)

    def test_silence_passes_an_expect_none_step(self):
        text, code = self.run_against()
        self.assertEqual(code, 0, text)
        self.assertIn("ok 1 - noip/discover: expect none", text)

    def test_an_answer_fails_an_expect_none_step(self):
        from test_dhcp import reply
        text, code = self.run_against([reply("OFFER")])
        self.assertEqual(code, 1, text)
        self.assertIn("not ok 1 - noip/discover: expect none", text)
        self.assertIn("received: 'OFFER'", text)


if __name__ == "__main__":
    unittest.main()
