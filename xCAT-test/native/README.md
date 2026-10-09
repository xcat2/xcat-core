# Native host tests

These tests use the source checkout with RPM tools, Linux namespaces or real
service binaries. They are separate from `unit/` and are not discovered by the
default pull-request unit run. Run them explicitly on a disposable Linux host.

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

## Package lifecycle

Run these cases as an ordinary user with unprivileged Linux namespaces enabled.
They use private filesystem, process and network namespaces, not host services.

On Debian or Ubuntu, install `bubblewrap`, `debhelper`, `devscripts`, `fakeroot`,
`quilt`, `ucf`, `debconf-utils`, `systemd`, `rpm`, `apache2`, `curl`,
`libcapture-tiny-perl` and `libfile-slurper-perl`, then run:

```
prove xCAT-test/native/xcatd_debian_lifecycle.t \
      xCAT-test/native/xcatd_restart_callers.t \
      xCAT-test/native/apache_package_lifecycle.t
```

On EL8 or EL10, install `bubblewrap`, `rpm-build`, `systemd`, `chkconfig`,
`initscripts`, `httpd`, `curl`, `tar`, `gzip`, `which`, `diffutils`, `procps-ng`,
`perl-Capture-Tiny`, `perl-File-Slurper` and `perl-Test-Simple`, then run:

```
prove xCAT-test/native/xcatd_rpm_lifecycle.t \
      xCAT-test/native/apache_rpm_configuration.t \
      xCAT-test/native/apache_package_lifecycle.t
```

These EL dependencies need EPEL plus PowerTools on EL8 or CRB on EL10.

Package transactions use native package tools and private package databases.
Dependency resolution is bypassed to isolate maintainer-script behavior.
Service registration uses real offline tools. Service dispatch uses command
fixtures, while header checks start real Apache on an isolated loopback port.
The service cases execute the installed unit's start command with a daemon
fixture. RPM upgrades also cover the old package-owned init-script layout.
The Debian Apache cases unpack built packages and execute their complete
maintainer scripts. Restart-caller cases execute complete Debian scripts and
RPM-rendered scriptlets without building the optional UI package.

The RPM Apache cases distinguish a root without `/proc` from a chroot with
`/proc` mounted and a different PID 1 root. Debian and restart-caller cases
check dispatch with and without `/proc`; these do not qualify chroot safety.

The configuration cases exercise EL and SUSE build-macro selections on native
EL RPM tools. The legacy release identities select init policy, not a native
EL6 or Ubuntu 14.04 environment. These cases do not qualify native SUSE package
transactions, dependency resolution, a running xcatd daemon, or machine boot.
The namespace fixture targets merged-/usr hosts. Container runs need namespace
permissions and an init process that reaps orphaned children.
