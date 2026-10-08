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

The image caller tests need `bubblewrap`, `cpio`, `gzip`, RPM tools and the
Perl modules used by the unit suite, including DBD::SQLite, XML::Simple and
Net::DNS:

```
prove xCAT-test/native/genimage_network_drivers.t \
      xCAT-test/native/el10_image_package_policy.t
bats xCAT-test/bats/networkmanager_postscript.bats
```

These cases run complete callers in private filesystems with no network.
They check driver configuration after real driver-disk loading, media-import
records, parsed RPM installation scriptlets and rendered installation postscripts.
External package downloads, service management, disk mounts and initrd creation
use command fixtures. These cases do not boot an image or qualify hardware.
The two Perl image caller tests fail if run as root.

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
