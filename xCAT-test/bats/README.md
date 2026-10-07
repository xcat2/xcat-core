# xCAT-test/bats

Shell-script unit tests live here and run with:

```bash
bats -r xCAT-test/bats
```

The GitHub Actions `xcat_test` workflow runs this command after the Perl `.t`
unit tests. Use BATS for shell behavior that can be exercised from the source
tree without an installed xCAT, a live management node, or real services.

Prefer sourcing an existing shell library or sourceable script and calling the
function under test. Keep reusable install-template helpers in
`xCAT-server/share/xcat/install/scripts/scriptlib`, and reusable postscript
helpers in `xCAT/postscripts/xcatlib.sh`. Use scratch directories and shadowed
commands so tests cannot write to the host.

Extraction helpers in `helpers/shell_source.bash` are only for legacy code that
cannot safely be sourced yet. Do not add Perl `.t` tests that grep shell source
when the behavior can be tested with BATS.

## Postscript sandbox prerequisites

`otherpkgs_upgrade_scope.bats` and `routeop.bats` run complete postscripts in
Linux filesystem and network namespaces. Their `/etc` writes stay inside test
fixtures. They require Bubblewrap, Bash, GNU core utilities, grep, sed, and
permission to create user namespaces. The CI workflow installs Bubblewrap and
enables those namespaces.

Missing prerequisites fail these tests without stopping unrelated test files.
Non-Linux hosts report a skip. Set `TMPDIR` to a writable, executable filesystem
if the default temporary directory is mounted with `noexec`.

## Genesis sandbox prerequisites

`genesis_bmcsetup_users.bats` and `genesis_getadapter.bats` run the complete
checkout scripts with private filesystem, process, and network namespaces.
They replace hardware and transport commands, not the scripts under test.
The fixtures do not contact a BMC or transmit an adapter request.

These tests require Linux, bats-core 1.4 or newer, Bubblewrap, Bash, GNU core
utilities, awk, grep, sed, and user namespace support. The adapter tests also
require `cmp` from diffutils. The CI environment provides these dependencies.
Missing prerequisites fail on Linux; non-Linux hosts report a skip.
