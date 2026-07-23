# xCAT-test/integration

Integration tests. These run against an **installed management node** -- they need a
real xCAT installation, and depending on the test a populated `/install`, a service
binary they can execute, or a live daemon.

They are *not* run by the GitHub Actions pull request workflow, which has no
management node. They are driven by `xcattest` through the testcase in
`../autotest/testcase/integration/`, which proves the copy installed by the
`xcat-test` package:

```
prove -I/opt/xcat/lib/perl -I/opt/xcat/lib/perl/xCAT \
      -r /opt/xcat/share/xcat/tools/autotest/integration
```

Run the case on an MN with:

```
xcattest -f <cluster.conf> -t integration_tests
```

Note the `-I` flags: unlike the unit tests these run from the installed location, so
they pick up xCAT modules from `/opt/xcat/lib/perl` rather than from a source tree.

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
