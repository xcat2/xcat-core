# xCAT-test/integration

Integration tests. These run against an **installed management node** -- they need a
real xCAT installation, and depending on the test a populated `/install`, a service
binary they can execute, or a live daemon.

The Perl tests are driven by `xcattest` through the testcase in
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

The case checks `rc==0` and `output=~Files=12,`. The file count checks that `prove`
found all twelve files, which catches a packaging regression or a test renamed away from
`.t` without updating the count. It does not prove that environment-gated cases ran;
inspect the TAP output for skips. **Add to that number when you add a test.** A missing
directory is already caught by `rc==0` -- `prove -r` on a path that does not exist exits
2.

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
| `dhcp_isc_config_validation.t` | a `dhcpd` binary that can read the generated config, as root |
| `dhcp_isc_ipxe_leases.t` | `dhcpd` and `omshell`, root, and `ip netns` for a private network namespace |
| `dhcp_ipxe_dispatch.t` | `dhcpd` with `omshell`, or `kea-dhcp4`, root, and `ip netns` for two private network namespaces |
| `dhcp_dhcpv6_duid.t` | `dhcpd` with `omshell`, or `kea-dhcp4` and `kea-dhcp6`, root, and `ip netns` for two private network namespaces |
| `dhcp_kea_config_validation.t` | a `kea-dhcp4` binary that can read the generated config |
| `dhcp_kea_control_agent_smoke.t` | live `kea-dhcp4` and `kea-ctrl-agent`, root, and the Kea host-commands hook |
| `html_form_runtime_dependency.t` | the installed `HTML::Form` module |
| `openeuler_package_postscripts.t` | Linux root, private mount namespaces and DNF; tests complete package postscripts with command doubles and an isolated repository directory |
| `openeuler_postscript_repositories.t` | Linux root, private mount namespaces, DNF and RPM signing tools; tests actual signed repository transactions in isolated install roots |
| `syncfiles_delivery.t` | a disposable management node, service node and compute node, certificate policies and SSH copy access; opt-in |
| `wsapi_apache_access.t` | an Apache binary and its modules; reads `xcat-ws.conf` from the source tree, so `github_action_xcat_test.pl` runs it from the checkout and the installed copy skips |
| `xcatd_dispatch_redaction.sh` | a live `xcatd`, syslog delivery to `/var/log/xcat/cluster.log`, and root |

Run `xcattest -t xcatd_dispatch_redaction` to check password redaction in the
daemon's syslog output. This separate case has the `ci_test` label. It enables
`site.xcatdebugmode`, creates a temporary node, and restores the setting and removes
the node on exit. Run it without concurrent changes to `site.xcatdebugmode`.

## Environment guards

`openeuler_postscript_repositories.t` builds and signs RPM fixtures and runs real
DNF transactions. Enable it explicitly on a disposable openEuler host:

```
sudo env XCAT_NATIVE_REPOSITORIES=1 prove -v \
    xCAT-test/integration/openeuler_postscript_repositories.t
```

The Perl test builds the RPM fixtures directly. Its DNF adapter records arguments
and uses only local fixture repositories, with a fixed fixture release version.

Tests with optional runtime dependencies guard with `plan skip_all` -- an MN with no
Kea installed should skip the Kea tests, not go red. The `HTML::Form` test is different:
it verifies a required installed dependency and fails when that module is absent. A
skip in this directory is therefore expected and normal.

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

## Syncfiles delivery lab

Run `syncfiles_delivery.t` only in a disposable three-node lab. It sends real
`syncfiles` and `updatenode -F` requests, and runs real SSH/rsync copies. Do not
point it at a shared or production cluster.

Prepare the lab before enabling the test:

- Install xCAT on the management and service nodes, and the xCAT Perl client
  modules on the compute node. Install Perl `File::Slurper`, `Capture::Tiny`,
  `JSON::PP`, `timeout`, SSH/SFTP and rsync. The management and service nodes
  must have the normal `updatenode` postscript files and reachability tools.
- Configure name resolution and route the compute node through the service node
  in `noderes.servicenode` and `noderes.xcatmaster`. Give the compute node a
  dedicated osimage with exactly one synclist: `<work>/synclist`.
- Configure the service-node cache prefix in the test to match
  `site.SNsyncfiledir` (default `/var/xcat/syncfiles`). Keep the daemon environment
  free of `DSH_*`, `DCP_*` and `RSYNC*` overrides.
- Use a lab CA and valid client certificates for `operator` and `denied`.
  Allow `operator` to run `syncfiles`, `updatenode` and `xdcp`. Leave `denied`
  unauthorized. On both the management and service nodes, remove the default
  unnamed `syncfiles` allow rule and any other rule that allows `denied`.
  This certificate-only fixture intentionally differs from the default policy,
  which allows the certificate-free `startsyncfiles` postscript request.
  Configure the normal trusted MN/SN certificate relationship.
  Store the client credentials and CA on the compute node; the test does not
  create certificates or change policy.
- Create the `operator`, `sender` and `receiver` Unix accounts. Give the
  management node root SSH access to the service and compute nodes, and give
  the service node SSH copy access to the compute node as `root`, `operator`
  and `sender`. Use lab-only keys and pinned host keys. Do not enable password
  authentication for this test.

Create a JSON configuration on the management node. For example:

```json
{
  "management": "mn",
  "service": "sn",
  "node": "cn",
  "work": "/tmp/xcat-syncfiles-fixture1",
  "cache": "/var/xcat/syncfiles",
  "operator": "/root/lab-certs/operator.pem",
  "denied": "/root/lab-certs/denied.pem",
  "ca": "/root/lab-certs/ca.pem"
}
```

Each client PEM contains its certificate and private key. Keep the credentials
private. The three host names must be distinct. The work path must be a new
directory directly under `/tmp`, named `xcat-syncfiles-` followed by letters or
digits. The test refuses existing work and cache paths, removes its request and
payload directories on exit, and fails if that cleanup fails. xCAT can retain
cache parent directories and generated `/tmp/rsync_*` command files outside
those directories. Remove the disposable nodes and credentials after testing.

Run as root on the management node:

```sh
XCAT_SYNCFILES_LIVE_CONFIG=/root/syncfiles-lab.json \
    prove -v xCAT-test/integration/syncfiles_delivery.t
```

The certificate cases check authorization under that restricted policy, MN/SN
staging, delivered bytes and file ownership. `syncfiles` requests root copies
regardless of the authenticated user; `updatenode` retains the authenticated
user unless its environment overrides the sender. The inherited-environment
cases call the real copy consumer on the service node without TLS; they test
copy identity precedence, not authentication. The unit test
`syncfiles_consumer_identity.t` checks both parsed identity variables and rejects
changes that overwrite nonempty inherited values.

This fixture does not cover the default certificate-free `startsyncfiles` path.

## What does not belong here

Anything that only needs the checkout. Those go in [`../unit`](../unit/README.md) and
run on every pull request, which is much faster feedback than waiting for a cluster
test.
