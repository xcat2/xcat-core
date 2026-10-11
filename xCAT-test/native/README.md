# Native host tests

These tests use the source checkout with RPM tools, Linux namespaces or real
service binaries. They are separate from `unit/` and are not discovered by the
default pull-request unit run. Run them explicitly on a disposable Linux host.

## Ubuntu media and image fixtures

The pull-request workflow runs these four tests explicitly:

```
prove xCAT-test/native/ubuntu_live_media_guardrails.t \
      xCAT-test/native/ubuntu_genimage_debootstrap_arch.t \
      xCAT-test/native/ubuntu_genimage_apt_mirror.t \
      xCAT-test/native/ubuntu_genimage_resolver_libs.t
```

They require Linux user namespaces, Bubblewrap, cpio, gzip, GNU timeout and
the system Perl in `/usr/bin` or `/bin`. Install the source-tree Perl dependencies,
including File::Slurper, DBI and DBD::SQLite, for that interpreter. Tools must be
in `/usr/bin`, `/bin`, `/usr/sbin` or `/sbin`. Run the tests as an ordinary user.
Missing Linux prerequisites fail the tests; other operating systems skip them.

The fixtures execute the checkout's unchanged Debian plugin and Ubuntu genimage
script with private filesystems and no network access. Media copying, database
updates, the image's APT sources.list and initrd archives are real. Decompression
and archive inspection are real too. The debootstrap command records its arguments;
the architecture test stops at its deliberate failure. The mirror test lets it
complete, replaces mount commands and stops at a deliberate apt-get update failure.
The initrd fixture supplies chroot ldd and depmod results. These tests do not install
packages, execute target-architecture binaries or prove that the generated image boots.

## Other native tests

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
