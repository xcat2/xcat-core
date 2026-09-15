# xCAT-test/bats

Shell-script unit tests live here. They run from the source tree, as a normal user or as root:

```bash
bats --timing --jobs 4 -r xCAT-test/bats
```

`--jobs` needs GNU `parallel`. BATS 1.10 rejects the packed form `-j4`; write `--jobs 4` or
`-j 4`. The GitHub Actions `xcat_test` workflow runs this command after the Perl `.t` unit tests.

Use BATS for shell behavior that can be exercised from the source tree without an installed
xCAT, a live management node, or real services. Prefer sourcing an existing shell library or
sourceable script and calling the function under test. Keep reusable install-template helpers in
`xCAT-server/share/xcat/install/scripts/scriptlib`, and reusable postscript helpers in
`xCAT/postscripts/xcatlib.sh`.

## Keep the test off the host

The helpers in `helpers/shell_source.bash` fail closed:

- `require_repo_file` fails the test when a checkout file is missing. Do not `skip` for a
  missing checkout file.
- `extract_shell_if_block FILE START [NTH TOTAL]`, `extract_line_range` and
  `extract_unique_line` fail when the text they look for occurs a different number of times than
  expected, or when the block does not end. Pin the number of occurrences, and pin the number
  of lines of a block the test evaluates.
- `sandbox_path TOOL...` prints a directory to use as the whole `PATH`, with the listed host
  tools and nothing else. `run_in_sandbox_path` runs a command with the tools in
  `SANDBOX_TOOLS`, under `run`. A command the test did not shadow is then "not found" instead of
  running on the host.
- `require_scratch_path` fails when a directory the code under test uses as a root is empty or
  outside `BATS_TEST_TMPDIR`.

`helpers/go_xcat.bash` reads `go-xcat` from the checkout and fails when a function it extracts
is missing, defined twice, or has no closing brace.

A shadowed `sleep` in a retry loop must count its calls and fail after a limit, so that a lookup
that never succeeds fails the test instead of hanging it. Use a pid that the test started and
reaped, not a fixed number that may belong to a host process.

Extraction helpers are only for legacy code that cannot safely be sourced yet. Do not add Perl
`.t` tests that grep shell source when the behavior can be tested with BATS.
