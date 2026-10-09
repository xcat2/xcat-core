# Native host tests

These tests use the source checkout with RPM tools, Linux namespaces or real
service binaries. They are separate from `unit/` and are not discovered by the
unit runner. CI selects specific cases explicitly; run the others on a
disposable Linux host.

Run the package and unprivileged namespace cases as an ordinary user:

```
prove xCAT-test/native/buildrpms_openeuler.t \
      xCAT-test/native/buildrpms_release_openeuler.t \
      xCAT-test/native/genesis_openeuler*.t \
      xCAT-test/native/openeuler_genimage_bootfiles.t \
      xCAT-test/native/openeuler_package_policy.t
```

Run the isolated system cases as root:

```
sudo prove xCAT-test/native/ip_forwarding.t \
      xCAT-test/native/openeuler_genimage_transactions.t \
      xCAT-test/native/openeuler_install_repositories.t \
      xCAT-test/native/openeuler_networking.t \
      xCAT-test/native/openeuler_xcatroot.t \
      xCAT-test/native/remoteshell_hostkeys_openeuler.t \
      xCAT-test/native/syslog_openeuler*.t
```

The PostgreSQL case starts a private server with only a Unix socket. Run it as
an ordinary user with `XCAT_TEST_PG_BINDIR` set to the directory containing
`initdb`, `pg_ctl`, `postgres`, `psql` and `createdb`:

```
XCAT_TEST_PG_BINDIR=/usr/bin prove xCAT-test/native/pgsqlsetup_native_schema.t
```

Check the TAP output for skipped prerequisites. A successful `prove` exit with
skipped cases does not qualify those cases.

## Profile artifacts

These cases render install profiles, run netboot postscripts, build a Debian
repository, and execute rendered Subiquity commands. Run them as an ordinary
user with Bubblewrap and unprivileged user namespaces enabled:

```
prove xCAT-test/native/install_profile_riscv64.t \
      xCAT-test/native/netboot_profile_riscv64.t \
      xCAT-test/native/builddebs_riscv64.t \
      xCAT-test/native/ubuntu_subiquity_template.t
```

The renderers need the xCAT Perl dependencies, DBD::SQLite, Capture::Tiny,
and File::Slurper. The Subiquity case also needs /usr/bin/python3 with PyYAML.
The Debian case needs debhelper, devscripts, fakeroot, and reprepro, and skips
on non-Debian hosts. Each case creates its own temporary files and database.
The temporary directory must allow execution; set TMPDIR if /tmp is noexec.

The Subiquity case replaces downloads and external commands, and uses a
loopback install-monitor peer. It does not install an operating system.
Architecture names in these fixtures do not qualify native firmware or boot
behavior on those architectures.
