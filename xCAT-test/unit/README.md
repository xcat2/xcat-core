# xCAT-test/unit

Unit tests. These run against the **source tree only** -- no xCAT installation, no
running daemons, no management node.

They are executed on every pull request by the `xcat_test` GitHub Actions workflow,
which calls `run_unit_tests()` in `github_action_xcat_test.pl`:

```
prove -r xCAT-test/unit
```

You can run exactly the same thing from a clean checkout:

```
cd <xcat-core checkout>
prove -r xCAT-test/unit
```

## What belongs here

A test belongs in `unit/` when everything it needs is in the checkout: plugin and
library sources, kickstart/preseed/subiquity templates, postscripts, packaging
metadata. Such a test asserts on rendered output or module logic and reaches the
repository root through `FindBin`:

```perl
use FindBin;
use lib "$FindBin::Bin/../../perl-xCAT";
use lib "$FindBin::Bin/../../xCAT-server/lib/perl";
```

Because of those `FindBin` paths the tests only work from a source tree. The copy
installed under `/opt/xcat/share/xcat/tools/autotest/unit` is not a substitute --
`../..` resolves to `/opt/xcat/share/xcat/tools` there and the tests die or silently
skip. The CI takes a copy of the checkout before the build for this reason; see
`preserve_source_tree()`.

## What does not belong here

Anything that needs an installed xCAT, a populated `/install`, a real service binary
or a live daemon. Those go in [`../integration`](../integration/README.md) and run on
a management node through `xcattest`. Both suites run on every pull request -- the
workflow installs xCAT on the runner and then runs the `ci_test` cases against it --
so putting a test in `integration/` does not cost it CI coverage. What differs is what
each suite is allowed to depend on, and that unit tests also run standalone from a
bare checkout with no xCAT at all.

The distinction matters because a test that needs an absent environment does not fail
-- it calls `plan skip_all` and reports as skipped. A handful of those in a suite of
several hundred assertions is easy to stop reading. Keeping the two kinds in separate
directories means a skip in `unit/` is a real signal rather than routine noise.

Guarding on a *source* file, on the other hand, is fine and common here:

```perl
plan skip_all => "compute.subiquity.tmpl not found" unless -f $tmpl_path;
```

That guard never fires when the tree is intact.
