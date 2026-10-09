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

## Genesis OpenEmbedded

`genesis_metadata.py` runs inside a Genesis KAS shell. It uses BitBake to
evaluate machine and package policy, install local-file recipes into temporary
directories, generate extension manifests and reject invalid extension
metadata. It does not extract or evaluate recipe source fragments.

For example, from the source checkout:

```sh
export KAS_WORK_DIR=/path/to/kas-work
export KAS_BUILD_DIR=/path/to/kas-build-x86_64
source_tree=$PWD
kas dump --format json xCAT-genesis-base/oe/kas/x86_64.yml >"${KAS_BUILD_DIR}.json"
kas shell xCAT-genesis-base/oe/kas/x86_64.yml -c \
    "GENESIS_ARCHITECTURE=x86_64 GENESIS_KAS_CONFIG='${KAS_BUILD_DIR}.json' python3 '${source_tree}/xCAT-test/native/genesis_metadata.py'"
```

Use the pinned KAS requirements and OpenEmbedded host prerequisites from
`xCAT-genesis-base/oe`. Run as an ordinary user with an executable temporary
directory. BitBake's build directory must use a supported local filesystem.
The `genesis_openembedded` workflow runs the metadata tests for x86, x86_64,
ppc64, ppc64le, armv7hf, aarch64, riscv64 and s390x.

`python3 xCAT-test/native/genesis_console.py` builds and installs the complete
console with Meson, then runs the installed program. It requires a C compiler,
Meson, Ninja, pkg-config, and development packages for Newt and systemd.

The unit test retains checks of the vendored release key, requested kernel
fragments and console service configuration. The BATS tests retain runtime,
console, hardware and packet behavior. None of these checks replaces a full
image build, inspection of its resolved kernel configuration or a boot test.
