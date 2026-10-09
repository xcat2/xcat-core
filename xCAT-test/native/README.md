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

The disk, kdump and sudoer cases require Bubblewrap, Capture::Tiny,
File::Slurper and sudo's `visudo`. Enable Linux user namespaces. Run the group
as root because the disk case creates dummy block-device entries:

```
sudo prove xCAT-test/native/getinstdisk_selection.t \
      xCAT-test/native/enablekdump_per_node.t \
      xCAT-test/native/sudoer_password_source.t
```

When the checkout is inside another user's private home, copy it as root to a
temporary directory under `/tmp` first. Root inside the test's user namespace
cannot traverse a private directory owned by that user. CI uses a root-owned
copy for this reason.

These cases run the unchanged scripts with private filesystems and no network.
Disk discovery, NFS mounts, credentials, account commands and service commands
use fixtures. The disk case never opens its dummy devices. The sudoer case
checks generated rules with the real `visudo` parser. These tests do not perform
an installation, capture a kernel crash or modify host accounts.

Check the TAP output for skipped prerequisites. A successful `prove` exit with
skipped cases does not qualify those cases.
