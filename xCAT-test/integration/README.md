# xCAT-test/integration

Integration tests. These run against an **installed management node** -- they need a
real xCAT installation, and depending on the test a populated `/install`, a service
binary they can execute, or a live daemon.

They are driven by `xcattest` through the testcase in
`../autotest/testcase/integration/`, which proves the copy installed by the
`xcat-test` package:

```
prove -I/opt/xcat/lib/perl -I/opt/xcat/lib/perl/xCAT \
      -r /opt/xcat/share/xcat/tools/autotest/integration
```

Run the case by hand on an MN with:

```
xcattest -f <cluster.conf> -t integration_tests
```

The case carries the `ci_test` label, so it also runs on every pull request: the
`xcat_test` GitHub Actions workflow installs and configures xCAT on the runner, which
makes that runner a (single node) management node, and then runs every `ci_test` case
against it.

Note the `-I` flags: unlike the unit tests these run from the installed location, so
they pick up xCAT modules from `/opt/xcat/lib/perl` rather than from a source tree.

The case checks `rc==0` and `output=~Files=3`. The second assertion is there because
`prove` exits 0 both when tests pass and when they all skip, so `rc==0` alone would let
the case report green having run nothing. Matching `Files=3` proves `prove` actually
found all three files, which catches a packaging regression or a file being renamed
without the count being updated here. **Add to that number when you add a test.** A
missing directory is already caught by `rc==0` -- `prove -r` on a path that does not
exist exits 2.

Note also that `github_action_xcat_test.pl` invokes each case through `sudo`, so in CI
these tests run as **root** while the unit tests run unprivileged. That is the right
way round -- integration tests legitimately need to write to places like `/etc/kea`,
whereas running the unit tests as root would let permission-related assertions pass
for the wrong reason.

## What belongs here

A test belongs in `integration/` when it needs something the checkout cannot provide:

| Test | Requires |
| --- | --- |
| `copycds_packages_integrity.t` | `/install` populated by a real `copycds` |
| `dhcp_kea_config_validation.t` | a `kea-dhcp4` binary that can read the generated config |
| `dhcp_kea_control_agent_smoke.t` | live `kea-dhcp4` and `kea-ctrl-agent`, root, and the Kea host-commands hook |

## Environment guards

Tests here still guard with `plan skip_all` so the case does not fail on a node that
legitimately lacks the dependency -- an MN with no Kea installed should skip the Kea
tests, not go red. A skip in this directory is therefore expected and normal, which is
precisely why these tests do not belong alongside the unit tests.

Which tests actually run consequently varies by node. On a GitHub runner, for example,
`/install` is empty so `copycds_packages_integrity.t` skips, while
`dhcp_kea_config_validation.t` does run because the case executes as root and can
therefore validate from `/etc/kea`.

`dhcp_kea_control_agent_smoke.t` is opt-in on top of that:

```perl
plan skip_all => 'set XCAT_KEA_LIVE_SMOKE=1 to run live Kea daemon smoke test'
  unless $ENV{XCAT_KEA_LIVE_SMOKE};
```

It starts real Kea daemons, so it stays off unless asked for. Do not enable it on a
node whose DHCP service is in use.

## What does not belong here

Anything that only needs the checkout. Those go in [`../unit`](../unit/README.md) and
run on every pull request, which is much faster feedback than waiting for a cluster
test.
