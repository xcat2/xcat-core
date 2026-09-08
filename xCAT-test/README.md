# xCAT-test

Unit tests that run from the source checkout are split by implementation
language:

| Test type | Location | Runner |
| --------- | -------- | ------ |
| Perl unit tests | `xCAT-test/unit/*.t` | `prove -r xCAT-test/unit` |
| Shell unit tests | `xCAT-test/autotest/bats/*.bats` | `bats -r xCAT-test/autotest/bats` |

Use Perl `.t` tests for Perl modules, Perl scripts, templates, and repository
artifacts. Use BATS tests for shell-script behavior that can be exercised from
the checkout by sourcing a shell library or script and shadowing external
commands.

Shell behavior should not be tested by Perl tests that grep shell source. Put
those tests under `xCAT-test/autotest/bats` instead.

See `unit/README.md` and `autotest/bats/README.md` for the detailed rules for
each unit-test suite.
