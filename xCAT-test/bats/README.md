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

`go_xcat_os_release.bats`, `go_xcat_activation.bats` and the full-script cases in
`postscripts_apt_get.bats` use the same namespace isolation. They require
bats-core 1.4 or newer. OS detection also requires GNU awk for the legacy
Red Hat release parser. Postscript cases require GNU diffutils.

`networkmanager_postscript.bats` renders complete installation postscripts in
private namespaces. It requires Bubblewrap, bats-core 1.4 or newer, user
namespaces and the xCAT Perl dependencies, including DBI and DBD::SQLite.

`go_xcat_os_release.bats` and `go_xcat_el_repo_check.bats` source the complete
go-xcat script. OS detection uses mawk when available, otherwise the host AWK.
The two legacy Red Hat version cases use GNU awk. CI installs both interpreters.
Package-manager commands are test doubles, so these cases check selection,
arguments and error handling, not repository
availability or package installation.

## Genesis startup

`genesis_ib_modules.bats` and `genesis_secondary_dhcp.bats` run the complete
`doxcat` script in a private filesystem and network namespace. They replace
external services and device commands, then check the boot interface and the
IPv4 and IPv6 DHCP requests. They do not contact a DHCP server or a BMC.

The startup cases require Linux, bats-core 1.4 or newer, Bubblewrap, Bash, GNU
core utilities, grep, sed, awk and permission to create user namespaces.
Missing Linux prerequisites fail these cases. Non-Linux hosts skip them.
The RPM prerequisite check requires `rpmspec` but does not use the sandbox.
Run containers with an init process to
reap children created by deliberate-fault tests.

## Genesis sandbox prerequisites

`genesis_bmcsetup_users.bats` and `genesis_getadapter.bats` run the complete
checkout scripts with private filesystem, process, and network namespaces.
They replace hardware and transport commands, not the scripts under test.
The fixtures do not contact a BMC or transmit an adapter request.

These tests require Linux, bats-core 1.4 or newer, Bubblewrap, Bash, GNU core
utilities, awk, grep, sed, and user namespace support. The adapter tests also
require `cmp` from diffutils. The CI environment provides these dependencies.
Missing prerequisites fail on Linux; non-Linux hosts report a skip.
The temporary filesystem must allow executable files.

The BMC cases check LAN values, device and channel selection, write retries,
configuration defaults, user selection, and vendor port commands. They assert
the commands issued by the complete script. They do not verify that physical
BMC firmware accepts those commands.

## Boot artifact and repository checks

`mknb_genesis_compression.bats`, `dhcp_http_port.bats` and
`go_xcat_common_repository.bats` require Linux, Bubblewrap and user namespaces.
They execute checkout code in isolated filesystems without contacting services.
Non-Linux hosts skip these cases; missing Linux prerequisites fail them.
The compression cases also need xz, gzip and cpio. They run as an ordinary
user so directory-permission failures can be exercised. Both lzma and xz
selection paths build real images, and the decoder checks the LZMA format.
