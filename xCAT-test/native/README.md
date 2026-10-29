# Native host tests

These tests use the source checkout with RPM tools, Linux namespaces or real
service binaries. They are separate from `unit/` and are not discovered by the
unit runner. CI selects specific cases explicitly; run the others on a
disposable Linux host.

The postinstall case requires bubblewrap and the Perl modules used by the xCAT
template renderer. It runs complete rendered installer and postboot scripts in
private filesystems, with doubles for downloads and service commands:

```
prove xCAT-test/native/postinstall_bootstrap.t
```

It can run as root or an ordinary user with user namespaces enabled. This case
checks service policy and ordering; it does not boot or reinstall an OS.
The client steps cannot access the source tree or the server postscripts directory.

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

The pull-request workflow runs these packaging cases explicitly as an ordinary
user:

```
prove xCAT-test/native/probe_package_payload.t \
      xCAT-test/native/release_repository.t \
      xCAT-test/native/package_relations.t
```

They need RPM build/query tools, cpio, createrepo_c, zstd, rsync, GnuPG, Python 3
with RPM bindings, user/mount namespaces, and the Perl modules Capture::Tiny,
Digest::SHA, File::Slurper, Parallel::ForkManager and XML::LibXML. The probe
command also needs `which`. The release test uses an ephemeral signing key and
removes its agent. These checks inspect real packages and repository output;
they do not qualify package installation on every target architecture. On EL8,
install both `python36` and `python3-rpm` to provide the interpreter and its RPM
bindings.

The release case also runs source-only finalization with unsigned and signed
binary RPMs, empty binary trees, and absent, retained and standalone aliases.
It checks that binary files and aliases retain their bytes, modes and timestamps
while source RPMs and metadata use a different signing key. This covers cached
source RPMs; it does not run mock or publish a repository.

The Debian probe permission test has a separate pull-request CI step. It needs
Debian build tools, BATS, bubblewrap, fakeroot, reprepro and
libfile-slurper-perl. Run it as an ordinary user on a Debian or Ubuntu host
with unprivileged namespaces enabled:

```
bats xCAT-test/native/probe_debian_permissions.bats
```

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
      xCAT-test/native/el10_image_package_policy.t \
      xCAT-test/native/rh_genimage_chroot_mounts.t
```

These cases run complete callers in private filesystems with no network.
They check driver configuration after real driver-disk loading, media-import
records, parsed RPM installation scriptlets and the mounts that a new RPM
image has when its packages install.
External package downloads, service management, disk mounts and initrd creation
use command fixtures. These cases do not boot an image or qualify hardware.
The Perl image caller tests fail if run as root.

The default BATS suite also runs `networkmanager_postscript.bats`. It renders
installation postscripts and checks their network configuration in isolation.
See `xCAT-test/bats/README.md` for its prerequisites.

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

The mock result directory case needs the mock Python library, and root for its
ownership checks. The staged sources case needs root to read the sources as uid
1000. The `xcat_test` workflow runs both as root in a Fedora container:

```
sudo prove xCAT-test/native/mock_resultdir_owner.t \
      xCAT-test/native/build_sources_other_uid.t
```

The PostgreSQL case starts a private server with only a Unix socket. Run it as
an ordinary user with `XCAT_TEST_PG_BINDIR` set to the directory containing
`initdb`, `pg_ctl`, `postgres`, `psql` and `createdb`:

```
XCAT_TEST_PG_BINDIR=/usr/bin prove xCAT-test/native/pgsqlsetup_native_schema.t
```

The pull-request workflow runs the liteimg archive case explicitly. It runs the
statelite plugin with real cpio, gzip and find, and needs the Perl modules of
the unit suite, including DBD::SQLite:

```
prove xCAT-test/native/liteimg_ramdisk_archive.t
```

Compressor and ctorrent fixtures record what nodes can download during the
pack, or fail on request. The image lock and the ilitefile query are test
doubles. This case does not boot the image.

The pull-request workflow runs the UFTP listener case explicitly. It starts the
checkout's `xcat-uftp-listener` on loopback addresses and sends it requests
over TCP. It needs Bubblewrap with unprivileged user namespaces, GNU timeout,
the loopback address 127.0.0.2, and the Perl modules of the unit suite,
including DBD::SQLite and Capture::Tiny. Run it as an ordinary user:

```
prove xCAT-test/native/uftp_listener.t
```

Fixtures replace `uftp` and `uftp_keymgt`. The `uftp` fixture records its
arguments, its host list and the bytes it reads from descriptor 3, or exits
or blocks on request. The case checks key creation, the runtime check on a
read-only log directory, sender processes, timeouts, shutdown and connection
limits. It does not send multicast or boot a node.

The disk, kdump, sudoer and remoteshell cases require bats-core 1.4 or newer,
Bubblewrap, GNU timeout, diffutils, Capture::Tiny, File::Slurper and sudo's
`visudo`. The remoteshell case also needs `/usr/bin/openssl` and `ssh-keygen`
with DSA, RSA, ECDSA and Ed25519 support.
Sandbox commands have a 45-second limit. Enable Linux user namespaces.
Run the group as root because
the disk-selection case creates dummy block-device entries:

```
sudo bats xCAT-test/native/getinstdisk_selection.bats
sudo prove xCAT-test/native/getinstdisk_installer.t \
      xCAT-test/native/enablekdump_per_node.t \
      xCAT-test/native/sudoer_password_source.t \
      xCAT-test/native/remoteshell_credentials.t
```

The BATS cases source the unchanged disk selector. Partition and udev fixtures
are the inputs; the selected disk file is the output. Each case runs twice
with awk discovery and twice without it. Discovery searches a private fixture,
not the host's `/usr` tree.

The separate Perl case renders and runs the RHEL 10 installer fragment. It
checks that the partition plan uses the selected disk. It needs the system
Perl with xCAT's dependencies, XML::Simple and DBD::SQLite. The sandbox does
not mount perlbrew or local::lib directories.

When the checkout is inside another user's private home, copy it as root to a
temporary directory under `/tmp` first. Root inside the test's user namespace
cannot traverse a private directory owned by that user. CI uses a root-owned
copy for this reason.

These cases run the unchanged scripts with private filesystems and no network.
Disk discovery, NFS mounts, credentials, account commands and service commands
use fixtures. The disk case never opens its dummy devices. The sudoer case
checks generated rules with the real `visudo` parser. The remoteshell case
generates disposable SSH keys and checks their installation through the real script.
These tests do not perform
an installation, capture a kernel crash or modify host accounts.

The SELinux policy case runs as root in a disposable EL10 container. It needs
`make`, `selinux-policy-devel`, `selinux-policy-targeted`, `libselinux-utils`,
`policycoreutils`, `attr` and Capture::Tiny. It installs the xCAT module into a
private copy of the targeted store, so the host policy does not change. Set
`TMPDIR` to a file system that stores `security.selinux` attributes, such as a
tmpfs:

```
TMPDIR=/mnt/labels prove xCAT-test/native/selinux_file_contexts.t
```

The case looks up labels in the compiled `file_contexts` and relabels a copy of
`/install` with `setfiles`. It does not need an enforcing kernel, and it does not
run the rpm scriptlets.

The repair case drives the procedure the SELinux page documents for a published
artifact that carries the wrong type:

```
TMPDIR=/mnt/labels prove xCAT-test/native/selinux_image_repair.t
```

It adds local file-context mappings with `semanage`, so it also needs
`policycoreutils-python-utils`. Those mappings go into the policy store of the
host, so the case refuses to run where SELinux is enabled, and it removes every
mapping it adds. `restorecon` is a no-op where SELinux is disabled, so the case
applies the mappings with `setfiles` and asserts that the merged `file_contexts`
answers what the store answers for each path it measures.

Check the TAP output for skipped prerequisites. A successful `prove` exit with
skipped cases does not qualify those cases.

## FIPS policy and discovery keys

Run the unchanged statelite and Cumulus callers in private filesystems:

```
prove xCAT-test/native/statelite_optional_hostkey.t \
      xCAT-test/native/fips_build_guard.t
bats xCAT-test/native/cumulus_discovery_key_failure.bats
```

These cases require Bubblewrap, GNU timeout, Bash and Linux user namespaces.
The Perl cases also require File::Slurper, Capture::Tiny and Parallel::ForkManager.
The Cumulus case requires bats-core 1.4 or newer, GNU core utilities, grep and awk.
It uses the shared shell sandbox and replaces OpenSSL with a failing command.
It checks the exit status and key-generation attempt. It also checks that
no listener helper remains and no listener starts. It does not exercise a
switch or its discovery network.

Run the package case as an ordinary user:

```
prove xCAT-test/native/fips_package_payload.t
```

It builds xCAT and Genesis scripts with the host's package tools, extracts the
packages, and runs `unit/fips_shell_runtime.t` against their libraries. Use
Debian build tools on Debian or Ubuntu, and RPM build tools with cpio and bzip2
on EL. Both routes need OpenSSL, File::Slurper and Capture::Tiny.
The check bypasses build dependencies and does not install either package.
It does not build or boot a Genesis image.

Run the crypto cases on both FIPS-enabled and non-FIPS hosts. A status-file
fixture selects the policy but does not enable FIPS in OpenSSL. Legacy RSA-1024
signing is skipped on FIPS hosts and must pass on the non-FIPS host.

## Package lifecycle

Run these cases as an ordinary user with unprivileged Linux namespaces enabled.
They use private filesystem, process and network namespaces, not host services.

On Debian or Ubuntu, install `bubblewrap`, `debhelper`, `devscripts`, `fakeroot`,
`quilt`, `ucf`, `debconf-utils`, `systemd`, `rpm`, `apache2`, `curl`,
`libcapture-tiny-perl` and `libfile-slurper-perl`, then run:

```
prove xCAT-test/native/xcatd_debian_lifecycle.t \
      xCAT-test/native/xcatd_restart_callers.t \
      xCAT-test/native/apache_package_lifecycle.t \
      xCAT-test/native/package_upgrade_logging.t
```

On EL8 or EL10, install `bubblewrap`, `rpm-build`, `systemd`, `chkconfig`,
`initscripts`, `httpd`, `curl`, `tar`, `gzip`, `which`, `diffutils`, `procps-ng`,
`perl-Capture-Tiny`, `perl-File-Slurper` and `perl-Test-Simple`, then run:

```
prove xCAT-test/native/xcatd_rpm_lifecycle.t \
      xCAT-test/native/xcatd_relocated_startup.t \
      xCAT-test/native/apache_rpm_configuration.t \
      xCAT-test/native/apache_package_lifecycle.t \
      xCAT-test/native/package_upgrade_logging.t
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

Upgrade logging cases run package transactions with a configuration-command
fixture. They check output, warnings, PID relocation, temporary files and the
different RPM and Debian failure policies. They do not run `xcatconfig` or
build a Genesis image.

The RPM Apache cases distinguish a root without `/proc` from a chroot with
`/proc` mounted and a different PID 1 root. Debian and restart-caller cases
check dispatch with and without `/proc`; these do not qualify chroot safety.

The configuration cases exercise EL and SUSE build-macro selections on native
EL RPM tools. The legacy release identities select init policy, not a native
EL6 or Ubuntu 14.04 environment. These cases do not qualify native SUSE package
transactions, dependency resolution, a running xcatd daemon, or machine boot.
The namespace fixture targets merged-/usr hosts. Container runs need namespace
permissions and an init process that reaps orphaned children.

## Genesis OpenEmbedded

`genesis_metadata.py` runs inside a Genesis KAS shell. It uses BitBake to
evaluate machine and package policy, install local-file recipes into temporary
directories, generate extension manifests and reject invalid extension
metadata. It does not extract or evaluate recipe source fragments.
The NetworkManager case supplies an installed-unit fixture and runs the
recipe's install append to check the wait-online policy. It does not verify
the unit format produced by an upstream NetworkManager build.
The POWER patch case keeps BitBake's machine prepends and replaces only the
upstream kernel task body with a no-op. It applies the real patch to a small
metadata fixture, checks repeat runs and verifies that patch errors propagate.
It does not run the complete upstream kernel configuration task.

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

`python3 xCAT-test/native/genesis_console_dialogs.py` needs the same build
dependencies plus the `pyte` Python package, bubblewrap,
systemd-journal-remote and journalctl. It runs the linked console in a
pseudo-terminal and checks help and diagnostics navigation, scrolling,
live status updates, diagnostic snapshots, return to the main screen, and
header identity changes and truncation. These cases run at 80, 100 and 240
columns. Journal and shell cases run at 100 columns.
The F3 cases check journal filtering, order, history limits, follow mode,
paused selection, navigation and reopening. Rollover cases check expired
entries, duplicate messages and wrapped lines. The F12 cases check cancellation,
confirmation, terminal input, successful and nonzero exits, repeated launches
and executable errors.
It checks termination from the main screen, not from inside a dialog.

The journal and shell cases need working Linux user and mount namespaces.
On Ubuntu 24.04, the CI job enables them with
`sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0`.
The journal cases import private journal files, including appends while F3
is open, and verify each import with journalctl. They do not start a journal
service or read the host journal. Missing tools or namespace support fail
the tests; they do not skip.
The shell cases mount a fixture directory over `/usr/libexec` in a private
namespace to replace the external shell launcher. The real console handles
confirmation, child execution, waiting and terminal restoration.
The per-test temporary root is the only writable host-backed directory.
The libexec mount is read-only. Other writable mounts are private.
The real maintenance shell is not run.

The Genesis runtime BATS cases need Bash, Perl, OpenSSL, coreutils, diffutils
and bubblewrap. The credential-file cases use a private `/etc` in a Linux
namespace. The credential-file case fails if bubblewrap or user namespaces
are unavailable; it does not skip.

The unit test retains checks of the vendored release key, requested kernel
fragments and console service configuration. The BATS tests retain runtime,
console, hardware and packet behavior. None of these checks replaces a full
image build, inspection of its resolved kernel configuration or a boot test.

## Profile artifacts

These cases render install profiles, run netboot postscripts, build a Debian
repository, and execute rendered Subiquity commands. Run them as an ordinary
user with Bubblewrap and unprivileged user namespaces enabled:

```
prove xCAT-test/native/install_profile_riscv64.t \
      xCAT-test/native/netboot_profile_riscv64.t \
      xCAT-test/native/netboot_profile_postinstall.t \
      xCAT-test/native/builddebs_riscv64.t \
      xCAT-test/native/ubuntu_subiquity_template.t
```

The renderers need the system Perl with the xCAT dependencies, XML::Simple,
DBD::SQLite, Capture::Tiny, and File::Slurper. The sandbox clears the environment
and does not mount perlbrew or local::lib directories. The Subiquity case also
needs /usr/bin/python3 with PyYAML; on EL8, install python36 for that path.
The Debian case needs debhelper, devscripts, fakeroot, and reprepro, and skips
on non-Debian hosts. Each case creates its own temporary files and database.
The temporary directory must allow execution; set TMPDIR if /tmp is noexec.
Sandbox commands require GNU timeout and have a 45-second limit.
Pull-request CI runs these cases and rejects whole-file skips.

The netboot case executes the selected postinstall file directly. Its private
/bin/sh uses Bash, as on EL, including when the test host uses another shell.

`netboot_profile_postinstall.t` runs the affected EL postinstall owners and
their distro and service aliases. It checks the resulting SELinux settings,
missing files, comments, repeated execution, permissions, ownership and host
sentinels. It uses the same sandbox and Perl dependencies. CI runs it on
Ubuntu, EL8 and EL10. It executes host tools against private image roots;
it does not boot the target architecture or verify kernel SELinux state.
Both Bash and dash are required. The firewalld cases cover regular files,
valid and dangling symlinks, absent entries and directories under both shells.
The unit files, unrelated links and host entries must remain unchanged.

The Subiquity case replaces downloads and external commands, and uses a
loopback install-monitor peer. It does not install an operating system.
Architecture names in these fixtures do not qualify native firmware or boot
behavior on those architectures.
