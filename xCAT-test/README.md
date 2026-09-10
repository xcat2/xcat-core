# xCAT-test

Unit tests that run from the source checkout are split by implementation
language:

| Test type | Location | Runner |
| --------- | -------- | ------ |
| Perl unit tests | `xCAT-test/unit/*.t` | `prove -r xCAT-test/unit` |
| Shell unit tests | `xCAT-test/bats/*.bats` | `bats -r xCAT-test/bats` |
| DHCP wire tests | `xCAT-test/dhcptest/` | `python3 -m unittest discover -s tests`, then `dhcptest run -i <nic> <conf>` |
| CLI functional tests | `xCAT-test/autotest/testcase/` and `xCAT-test/autotest/bundle/` | `xcattest -f <cluster.conf> -t <case>` or `xcattest -f <cluster.conf> -b <bundle>` |

Use Perl `.t` tests for Perl modules, Perl scripts, templates, and repository
artifacts. Use BATS tests for shell-script behavior that can be exercised from
the checkout by sourcing a shell library or script and shadowing external
commands.

Shell behavior should not be tested by Perl tests that grep shell source. Put
those tests under `xCAT-test/bats` instead.

`dhcptest` is the odd one out: its Python unit tests and `dhcptest validate`
run offline like the others, but its point is the third column -- driving real
DHCP transactions on a provisioning NIC and asserting on what came back. It
talks to the server only over the wire, so it is agnostic to which DHCP
implementation is answering and to xCAT itself.

See `unit/README.md`, `bats/README.md` and `dhcptest/README.md` for the
detailed rules for each suite.
