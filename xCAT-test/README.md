# xCAT-test

Unit tests that run from the source checkout are split by implementation
language:

| Test type | Location | Runner |
| --------- | -------- | ------ |
| Perl unit tests | `xCAT-test/unit/*.t` | `prove -r xCAT-test/unit` |
| Shell unit tests | `xCAT-test/bats/*.bats` | `bats -r xCAT-test/bats` |
| Black-box service tests | `xCAT-test/blackboxtest/` | `python3 -m unittest discover -s tests`, then `blackboxtest run <conf>` on a management node |
| CLI functional tests | `xCAT-test/autotest/testcase/` and `xCAT-test/autotest/bundle/` | `xcattest -f <cluster.conf> -t <case>` or `xcattest -f <cluster.conf> -b <bundle>` |

Use Perl `.t` tests for Perl modules, Perl scripts, templates, and repository
artifacts. Use BATS tests for shell-script behavior that can be exercised from
the checkout by sourcing a shell library or script and shadowing external
commands.

Shell behavior should not be tested by Perl tests that grep shell source. Put
those tests under `xCAT-test/bats` instead.

`blackboxtest` is the odd one out: its Python unit tests and `blackboxtest
validate` run offline like the others, but its point is the third column --
asking a management node what a booting node asks (DHCP, DNS, TFTP, HTTP,
xcatd) and asserting on the answers. It talks to the services only as a client,
so it does not depend on which DHCP server answers or on the xCAT database.

See `unit/README.md`, `bats/README.md` and `blackboxtest/README.md` for the
detailed rules for each suite.
