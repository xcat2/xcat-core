# xCAT-test/unit

Unit tests. These run against the **source tree only** -- no xCAT installation, no
running daemons, no management node. They are safe to run as a normal user and as root.

The `xcat_test` GitHub Actions workflow runs them on every pull request, from a copy of the
checkout taken before the build:

```
cd <xcat-core checkout>
prove --timer -j4 -r xCAT-test/unit
```

The same command works on any host that has the Perl modules the xCAT packages depend on. When
a test dies with `Can't locate Some/Module.pm`, install the package that provides that module.
As root, `unshare` and `mount` must also be available; see the sandbox section below.

## The first lines of every test

```perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/../lib";
use XCAT::Test::Source qw(repo_path slurp_repo_file);
```

xCAT modules set `$::XCATROOT` from `$ENV{XCATROOT}`, or `/opt/xcat`, and put
`$::XCATROOT/lib/perl` in `@INC` when they compile. On a host with xCAT installed, a test that
loads one of them without `XCAT::Test::Source` measures the installed product.
`XCAT::Test::Source`:

- points `XCATROOT`, `XCATCFG` and `TMPDIR` into a scratch directory of the test process;
- puts the checkout library directories first in `@INC`, removes `/opt/xcat`, and loads
  `xCAT_plugin::`, `xCAT_monitoring::`, `xCAT_schema::` and `Confluent::` from the checkout
  only;
- fails the test at exit when a module came from `/opt/xcat` or from outside the checkout.

Do not add `use lib` lines for `perl-xCAT` or `xCAT-server/lib/perl`, and do not set
`XCATROOT` or `XCATCFG` in a test. Use `repo_path` and `slurp_repo_file` for checkout files, and
`perl_command` to start a child perl.

`unit_suite_policy.t` checks every test file for three rules: `XCAT::Test::Source` is the first
module loaded, no test calls `BAIL_OUT`, and no test skips because a checkout file is missing.

## Running product code without reaching the host

A sandbox made of path rewrites and command stubs fails open: when a rewrite stops matching,
or the product calls a command the test did not stub, the code acts on the host. Use
`XCAT::Test::Sandbox`, which fails closed:

- `replace_required` dies when the string to rewrite does not occur;
- `assert_no_host_paths` dies when a staged script still names a host path;
- `stub_bin` builds a directory of stubs and allowed tools, and `run_confined` or
  `confined_command` runs a command with that directory as its only `PATH` and an empty
  environment. As root, the command also runs in private mount and network namespaces with host
  directories read-only, and a host without namespaces fails the test;
- `confine_self` runs a test that calls product Perl in process again inside those namespaces,
  as root.

Use a TEST-NET-1 address (`192.0.2.0/24`) for any server a test names.

## Fail, do not skip

A missing checkout file, an extraction that no longer matches, and a module the checkout needs
that does not load all mean the test covers nothing. Die in those cases. `die` fails only its
own file; `BAIL_OUT` stops every test file after it.

Skip only when the host lacks an optional tool the test uses, such as `rpmspec` or `netplan`,
or when the test needs input that is not in the checkout, such as installation media.

## What does not belong here

Anything that needs an installed xCAT, a populated `/install`, a real service binary or a live
daemon. Those go in [`../integration`](../integration/README.md) and run on a management node
through `xcattest`. Both suites run on every pull request. Unit tests are never run from the
installed tree.

Shell-script unit tests belong in [`../bats`](../bats/README.md) and run with BATS. Do not add
Perl `.t` tests that grep shell source when the behavior can be exercised by sourcing a shell
library or script and shadowing the external commands it calls.
