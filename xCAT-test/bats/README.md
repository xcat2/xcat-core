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

`otherpkgs_upgrade_scope.bats` runs the complete postscript in a Linux filesystem
sandbox because it writes to `/etc/yum.repos.d`. It requires Bubblewrap, Bash,
GNU core utilities, and permission to create user namespaces. The CI workflow
installs Bubblewrap and enables those namespaces.

Missing prerequisites fail this test without stopping unrelated test files.
Non-Linux hosts report a skip. Set `TMPDIR` to a writable, executable filesystem
if the default temporary directory is mounted with `noexec`.
