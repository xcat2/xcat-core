FreeBSD stateful installation
=============================

This installation path targets FreeBSD 15.1-RELEASE on amd64 nodes. The xCAT
architecture name is ``x86_64``. The management node and service nodes remain
Linux systems.

xCAT starts a scripted installation in mfsBSD. The installed system boots from
its own disk. The boot sequence is::

    PXE firmware -> xNBA -> FreeBSD loader -> mfsBSD -> bsdinstall -> local disk

This is not SAN boot. No remote block device supplies the installed root
filesystem. The DHCP ``root-path`` option supplies a TFTP directory to the
FreeBSD loader; it does not select an NFS root or an iSCSI disk.

Scope and requirements
----------------------

* Use ``netboot=xnba`` and an imported ``imagetype=freebsd`` installation image.
* Select each disk by its FreeBSD device name and hardware serial. Automatic
  disk selection is not available. A single-disk policy replaces that disk's
  contents. A new multi-disk policy accepts only blank initial disks.
* Select single-disk UFS or ZFS, a ZFS mirror, striped mirrors, or RAID-Z1/2/3.
  Multi-disk policies require a version 2 image with the current storage runtime.
  Encryption, separate boot pools, GEOM/UFS mirrors, and Linux ZFS provisioning
  are outside this implementation.
* Use IPv4 and one provisioning interface selected by MAC address. After disk
  boot, ``confignetwork`` can configure additional interfaces and static IPv6.
  The node name must
  resolve to that interface's address, and reverse resolution must identify the
  same xCAT node. Status callbacks must retain that source address without NAT.
* Use one installation owner per node. Nodes assigned to a service node require
  an explicit, single ``xcatmaster``. State and boot publication must run there.
* Serve DHCP, TFTP, and HTTP from that same host. Remote file-service offload and
  automatic controller failover are not available.
* Use an isolated, trusted provisioning network. Configuration and release sets
  use HTTP; the loader pins the configuration checksum and the installer checks
  the release-set checksums. These checks do not authenticate the provisioning
  network itself.
* Supply plain SSH public keys. Password login is disabled on the installed
  system. Use native FreeBSD scripts and the package lists described below.
  Diskless images and FreeBSD service-node installation are outside this path.

Image definition versions
-------------------------

An unset or empty ``imageversion``, or the value ``1``, selects the legacy
definition. Its ``pkgdir`` is the combined mfsBSD boot and release-set bundle.
The installation steps below describe this version.

``imageversion=2`` separates the boot artifact and package repositories:

.. list-table:: Version 2 image attributes
   :header-rows: 1

   * - Attribute
     - Meaning
   * - ``bootdir``
     - One imported mfsBSD boot artifact.
   * - ``pkgdir``
     - One imported pkgbase repository role.
   * - ``pkglist``
     - Ordered base-component list files.
   * - ``otherpkgdir``
     - Ordered DVD application and supplemental repository roles.
   * - ``otherpkglist``
     - Ordered application-package list files.

All nonempty values use absolute paths. List attributes use commas between
paths. Paths cannot contain empty, dot, or dot-dot components or control
characters. Each path is limited to 4096 characters. Duplicate list entries
are rejected when setting a definition. Appending and removing entries use
the existing xCAT list operations, then validate the resulting definition.

Version 2 installation requires a compatible boot runtime and imported,
verified repositories. Preparation resolves the package selection and binds
the resulting plan to the installation generation. Importing an application
repository does not select all its packages.

Version 2 fields may be empty while preparing a definition. Legacy definitions
must leave ``bootdir``, ``pkglist``, ``otherpkgdir`` and ``otherpkglist`` empty.
A downgrade to version 1 must clear those fields in the same request. Changing
the version does not convert the object named by ``pkgdir`` into another type
of artifact. ``template``, ``partitionfile`` and ``osimage.environvar`` retain
their existing storage locations.

FreeBSD definitions require the exact value ``imagetype=freebsd``. Do not
change image families in place with ``chdef`` when either family is FreeBSD.
Use an explicitly replaced definition instead. ``mkdef -f`` checks the new
FreeBSD definition before removing the previous one. This check does not make
the database replacement transactional.

Import native release repositories
----------------------------------

``copycds`` accepts FreeBSD 15.1-RELEASE amd64 release media independently of
the mfsBSD installer. Base-only media supplies the pkgbase repository. DVD
media also supplies the complete application repository. Neither import
selects a boot artifact or packages to install.

Prepare a Linux-native ``pkg`` 2.8.2 executable and its required libraries on
the management node. ``copycds`` does not install this preparation tool.
Record the executable SHA256. When using a separate library directory, record
its ``xCAT::FreeBSDRepo::snapshot_tree`` digest, not one library's SHA256.
Native import checks these pins and uses private package databases and caches.
It does not install FreeBSD packages into the management node.

Authenticate the ISO checksum before approving its contents. Inspect that
same protected media::

    copycds -i /srv/iso/FreeBSD-15.1-RELEASE-amd64-disc1.iso

The output identifies the release, architecture, repository roles and
``TREE_DIGEST``. This digest covers the selected release files and repository
trees. It is not an ISO checksum. Inspection does not approve media, execute
the native tool or register an image.

Create a protected JSON policy. Replace the digest placeholders with the
verified values. Replace the tool paths with the prepared native tool::

    {
      "format": "xcat-freebsd-import-policy-1",
      "tool": {
        "path": "/opt/freebsd-pkg/sbin/pkg",
        "sha256": "<executable-sha256>",
        "library_directory": "/opt/freebsd-pkg/lib",
        "library_digest": "<library-tree-digest>"
      },
      "releases": {
        "<selected-tree-digest>": { "iso_sha256": "<authenticated-iso-sha256>" }
      },
      "repositories": {}
    }

All digests use 64 lowercase hexadecimal characters. Import-only policies can
omit both library fields when a separate library directory is not required.
Package planning requires both library fields. Empty approval maps are
valid. Unknown fields and unapproved release trees are rejected.

The policy must be a nonsymlink regular file with one link, at most 1 MiB,
and no group or other write permission. Its owner must be root or the importing
user. Ancestors must also be protected and nonsymlinked. Configure its location
and import the approved media::

    chtab key=freebsdimportpolicy site.value=/etc/xcat/freebsd-import.json
    copycds /srv/iso/FreeBSD-15.1-RELEASE-amd64-disc1.iso

The policy's ISO checksum is operator-recorded provenance. ``copycds`` checks
the approved selected-tree identity but does not authenticate that recorded
ISO checksum. It validates native catalogues and archives before publishing
the repositories below the configured installation directory.

The generated version 2 image names its base role in ``pkgdir``. A DVD import
also sets ``otherpkgdir`` to its application role. ``bootdir``, ``pkglist`` and
``otherpkglist`` remain unset. The version 2 installation restriction above
still applies.

``-o`` registers only the distribution. A later ordinary import can add the
image definition. ``-w`` rejects an existing publication. An ordinary repeat
import verifies existing content and preserves administrator-selected lists,
repository order and other mutable image settings. A registration failure
retains the verified publication and reports any failed database cleanup.

A later DVD import creates a separate image and reports its application role.
It does not change an earlier base-only image. Use the existing ``chdef -p``
list operation to add that role to the desired image's ``otherpkgdir``.
Storing this reference does not install packages or verify their dependencies.
The native import path does not support ``-n``, ``-a``, ``-p`` or ``-s``.

Plan an image's packages
------------------------

``freebsdrepo plan <osimage>`` resolves the package selection of an existing
version 2 installation image. It reads the image without changing its rows.
The image must target FreeBSD 15.1-RELEASE amd64 and must not be disabled.
The command does not require boot media, a template or a disk policy.

Build the Linux-native ``freebsd-pkg-resolve`` executable from
``src/freebsd-pkg-resolve.c`` in this xCAT source tree. Use the ``pkg`` 2.8.2
source at commit ``aec0cdcbdaba1f9511dabad38f1097b0a373c0f2``. Its Linux build
requires a C compiler, make, m4, pkg-config, and development files for libbsd,
libarchive, zlib, bzip2, liblzma and OpenSSL. Planning also requires binutils
``/usr/bin/readelf``.

Build ``pkg`` in a separate directory. Install its prefix with administrator
privileges. Keep the build directory for its static libelf archive::

    /path/to/pkg-source/configure --prefix=/opt/freebsd-pkg --with-libarchive.pc --with-openssl.pc
    make
    make install

From the xCAT source directory, build the resolver::

    cc -std=c11 -Wall -Wextra -Werror -I/opt/freebsd-pkg/include \
      src/freebsd-pkg-resolve.c -L/opt/freebsd-pkg/lib \
      -Wl,-rpath,/opt/freebsd-pkg/lib -Wl,--export-dynamic \
      -lpkg /path/to/pkg-build/external/libelf/libelf.a -lbsd \
      -o freebsd-pkg-resolve

Install the result with administrator privileges::

    install -d -m 0755 /opt/freebsd-pkg/bin
    install -m 0755 freebsd-pkg-resolve /opt/freebsd-pkg/bin/freebsd-pkg-resolve

The executables, library tree and their ancestors must be owned by root or
the server-side user and protected from group or other writes. Executables
must be nonsymlink regular files with one link. Library links must stay within
the protected tree. Do not execute tools from a user's build directory.
Planning rejects library search paths outside the pinned directory, including
``$ORIGIN`` paths. The Linux host's program loader and system libraries remain
trusted dependencies. The library-tree digest does not pin host libraries,
including libarchive, OpenSSL, libbsd and libc.

Record executable SHA256 values after installation. Obtain the library-tree
digest with ``freebsdrepo inspect /opt/freebsd-pkg/lib``. Set the policy's
``tool.path`` to the installed ``pkg`` executable, normally
``/opt/freebsd-pkg/sbin/pkg``. Add the resolver as a top-level policy member::

    "solver": {
      "path": "/opt/freebsd-pkg/bin/freebsd-pkg-resolve",
      "sha256": "<solver-executable-sha256>"
    }

Import operations do not require this member. Planning checks both native
executable pins and the required library-tree pin. It does not download
tools, consult public repositories or install packages on the management node.

Set ``pkgdir`` to the imported ``base`` role. Set ``otherpkgdir`` to any imported
DVD ``applications`` and supplemental ``repository`` roles, in the required
order. At most 32 roles are accepted, including the base role. Repositories
must contain all archives needed by the selected dependency closure.
Earlier repositories take priority for explicit application roots. Native
dependency resolution can select a dependency from its parent's repository,
even when an earlier repository contains that dependency. The plan records
the selected provider for every package.

Create protected list files on the management node. ``pkglist`` contains base
component names, such as ``base``. An empty file requests only the mandatory
minimal-system, kernel and package-manager roots and their dependencies.
``otherpkglist`` is optional and contains application package names, such as
``bash``. For example::

    chdef -t osimage freebsd-compute pkglist=/etc/xcat/freebsd/base.pkglist otherpkglist=/etc/xcat/freebsd/apps.pkglist
    freebsdrepo plan freebsd-compute

List files must be nonsymlink regular files with one link, owned by root or
the command's server-side user, with no group or other write permission.
Their ancestors must be protected and nonsymlinked. Limits are 64 files per
list attribute, 1 MiB per file, 8 MiB across both attributes and 8192 explicit
roots. The expanded native request also has an 8192-package limit, including
mandatory roots and component expansion. Repeated paths and duplicate roots
are rejected. The resolved dependency closure is limited to 8192 packages.
The serialized plan is limited to 16384 records and 8 MiB. Exceeding these
limits stops resolution or plan publication.

Use UTF-8 and LF line endings, including a final LF in every nonempty file.
Blank lines and comments beginning with ``#``, optionally preceded by spaces
or tabs, are ignored. Data lines are literal names: spaces are not trimmed
and commas do not split names. ``#INCLUDE``, ``#INCLUDE_*``, ``#ENV`` and
``#NEW_INSTALL_LIST`` directives are not supported. These reserved comment
prefixes are checked without regard to case. Selection order follows file
order, then line order within each file. Diagnostics identify invalid list
positions without copying their contents.

``kernel-dbg`` requires an available kernel debug package. The ``debug``
modifier adds available debug packages for selected base sets. Sets such as
``src`` and ``tests`` need no debug counterpart.

The command reports ``Package plan:`` and ``SHA256:``. The immutable plan is
published at ``<installdir>/freebsd15.1/x86_64/plans/<sha256>.plan``. It pins the
resolved package identities, source repositories and archive checksums. An
unchanged repeat selection verifies and reuses that plan. Missing packages,
unsatisfied dependencies and altered repository content stop publication.

To request failure details, authenticate to xCAT as root and add
``--diagnostics``::

    freebsdrepo plan freebsd-compute --diagnostics

A failure may add a ``DIAGNOSTICS:`` JSON report to standard output. The
original standard error and nonzero exit status remain unchanged.
The report can name unavailable selections or missing imported catalogue
name references, including references from unselected packages. It does not
explain the native solver's decision. Protect captured output because these
names come from protected inputs. See ``freebsdrepo(8)`` for report status
and size limits.

A successful plan does not arm a node or write a target disk. Use ``nodeset``
to prepare the node's installation.

Update packages on an installed node
------------------------------------

Set the installed node's image to the intended protected repositories and
package lists. Update base packages, application packages, or both::

    updatenode node01 -P ospkgs
    updatenode node01 -P otherpkgs
    updatenode node01 -S

The stock ``ospkgs`` selects base packages. The stock ``otherpkgs`` selects
application packages and their dependencies. ``-S`` selects both scripts and
updates the union of their package selections. An empty application list
produces a completed operation with zero package changes. Repository flags
on these scripts, such as ``--keeprepo``, are rejected before the package
operation. Configure repositories through the image attributes instead.

The package operation completes before the selected scripts run. Each stock
package script reports the bound result, including installed package, change
and action counts. The installed count covers the full node roster; the
update may select only part of that roster. An unchanged selection performs
no package actions.

An empty ``-P`` selection and section selectors use the rendered template's
entries. xCAT seals that selection and the script files before resolving the
package operation. Administrator replacements for the package scripts or
their native adapter retain their custom behavior. A selection without a
stock package script verifies the image's package prerequisite before running
its scripts.

When ``-S`` and ``-P`` are combined, xCAT prepares both passes, runs the
software pass, then runs the separate postscript selection. A failed software
pass stops the later pass. ``-F`` performs file synchronization after
preparation and before either pass.

Within each owner's request, FreeBSD nodes are processed sequentially. A
pending node delays later nodes until its run finishes or observation times
out. ``-t SECONDS`` sets the observation timeout for each run; the default is
3,600 seconds. Individual transport operations have separate deadlines and
can extend the elapsed time. Use separate commands on disjoint node sets
when the nodes must proceed independently.

If another worker holds the node lock, the command reports that the node is
busy and retries delivery within the observation timeout. This includes a
pending boot run. The waiting request keeps its run identity and does not
start scripts until the node lock is available. On timeout, use the printed
``--freebsd-run`` command to continue observing the same request.

The command prints each run identity. To resume observation of a retained
run without selecting another package operation or replaying completed
scripts, use one node and omit ``-F``, ``-S`` and ``-P``::

    updatenode node01 --freebsd-run RUN_ID

If a run was interrupted, inspect its retained results before releasing it
for reporting::

    updatenode node01 --freebsd-run RUN_ID --freebsd-release

Release normally requires a different boot from the one that started the run.
A supervised run can also be released on the same boot when the worker can
acquire a fresh node lock, verify that the original worker has stopped, and
validate completion observations for every command. A process-query error or
missing completion observation refuses this path. Older runs without those
observations still require a reboot.

Completed entries keep their recorded exit status. Unfinished entries remain
uncertain, and the command returns a nonzero status. Release does not restart
scripts. Resolve the uncertain effects before selecting a new update operation.
The command prints the retained run's diagnostic directory and recovery command
before it attempts to collect uncertain evidence. Collected reports include
available framework and supervisor diagnostics.

When package work has completed and all command completion observations are
available, a driver failure or an error while completing the run produces a
terminal failed result.
It does not require explicit release. The report preserves completed script
statuses and leaves unfinished scripts uncertain or not run. A missing
completion observation instead leaves the run uncertain and requires the
recovery command above.

When retained records prove that package application never started, release
keeps the previous package provenance and records that decision in the report.
This permits release after an early crash or a lost rejection response. It does
not change the interrupted run to a successful run.

If the package operation was interrupted, release also reconciles package
provenance against the retained request and the previous managed state. Changed
identities require matching archives and a complete action plan from that
operation. Recovery does not adopt unchanged packages that xCAT did not manage.
The report identifies recovered provenance separately from uncertain execution.
For a nonempty operation, previously managed packages that were already removed or
changed before that operation are excluded from its recovered ownership record.
The recovery log identifies those exclusions. Empty requests still require their
previous managed identities. Operations rejected before application retain the
previous ownership record.

Recovery does not repeat package scripts or certify their effects. Inspect and
repair those effects before requesting another operation. A partial upgrade
can leave some packages at their previous versions. Repeat-boot verification
checks the recovered managed identities. It does not complete the pending
upgrade. A new ``updatenode -S`` request can install the remaining packages.
Packages already at the requested identity do not repeat their package scripts.
Later successful operations do not change the interrupted run's outcome.

Release refuses recovery when its retained inputs cannot establish provenance
or deferred package triggers remain pending. Inspect the release diagnostic and
the attempt records below ``/var/db/xcat/postscripts/runs/RUN_ID/packages``.
Preserve failed ``recovery.*`` directories and their logs before resolving the
reported condition. A retry creates a fresh attempt or finishes publication of
the validated recovery record. Keep the original run records and payloads.

If damaged records continue to prevent release, stop retry clients and preserve
the node's ``/var/db/xcat/postscripts``, ``/var/db/xcat/pkgbase-install`` and
``/var/db/pkg`` directories with ownership and permissions intact. Use rescue
media to copy them from a read-only filesystem when the node cannot provide a
stable copy. Retain a verified copy outside the node before making repairs.

Restore a damaged record only from a verified copy taken before the damage,
from that same run and snapshot, then retry release. Do not fabricate action or rejection records or
delete the active run to bypass recovery. If no valid copy exists, restore a
consistent system backup that includes installed files, the package database
and xCAT records from the same checkpoint, or provision a fresh target disk set.
The new multi-disk policies still reject existing layouts; recovery does not
grant permission to erase them. Preserve the interrupted installation's evidence
before replacing it.

Import a version 2 boot artifact
--------------------------------

``copycds`` also accepts boot-only media with an ``xcat-mfsbsd-2`` manifest.
It validates the FreeBSD 15.1-RELEASE amd64 boot files, the required mfsBSD
source commit and the checksummed ``xcat/runtime.tsv`` descriptor. This format
does not contain release sets or package repositories.

The import reports a ``bootdir`` below
``<installdir>/freebsd15.1/x86_64/boot/<full-digest>``. It does not register a
distribution or image, replace ``pkgdir``, or attach itself to an existing
image. ``-o`` does not change this behavior. ``-i`` inspects without importing;
``-w`` rejects an existing destination. An ordinary repeat import verifies the
published files before reusing the destination.

Descriptor validation checks the declared runtime contract, required file
entries and checksum syntax.
It does not inspect those files inside the compressed RAM root. Build the
artifact with ``--pkgbase`` as described below. Changing a legacy manifest's
version does not convert its runtime into a version 2 boot artifact.

Build the native package resolver
---------------------------------

Version 2 boot media requires a FreeBSD-native resolver built from this source
tree. Build it as root on FreeBSD 15.1-RELEASE amd64, inside a separate release
root. Use a verified ``base.txz`` and its unmodified release compiler.

The build uses pkg 2.6.2 and the pkg port at commit
``40e2a735d862a58c16471bae506a4ff683cd0daf``. The script checks the source,
compiler, library and output checksums. An input or output mismatch stops the
build. Keep its fixed internal paths, which affect the binary checksum.

Prepare the release root and copy the xCAT sources::

    xcat_source=/path/to/xcat-core
    release_sets=/path/to/verified/FreeBSD-15.1-RELEASE
    resolver_root=$(mktemp -d /var/tmp/xcat-freebsd-resolver.XXXXXX)
    tar -xpf "$release_sets/base.txz" -C "$resolver_root"
    resolver_inputs=$resolver_root/work/recipe-inputs
    mkdir -p "$resolver_inputs/ports-mgmt/pkg/files"
    cp "$xcat_source/src/build-freebsd-pkg-resolve.sh" \
      "$xcat_source/src/freebsd-pkg-resolve.c" \
      "$xcat_source/src/freebsd-pkg-native.c" "$resolver_inputs/"
    cp "$xcat_source/xCAT-server/share/xcat/install/freebsd/patches/pkg-2.6.2-apply.patch" \
      "$resolver_inputs/"

Download the pinned public inputs::

    fetch -o "$resolver_inputs/freebsd-pkg-2.6.2_GH0.tar.gz" \
      https://codeload.github.com/freebsd/pkg/tar.gz/2.6.2
    ports_source=https://raw.githubusercontent.com/freebsd/freebsd-ports/40e2a735d862a58c16471bae506a4ff683cd0daf/ports-mgmt/pkg
    for name in Makefile distinfo files/patch-libpkg_libpkg.ver files/patch-src_Makefile.autosetup; do
        fetch -o "$resolver_inputs/ports-mgmt/pkg/$name" "$ports_source/$name"
    done

Run the build in the release root. The device filesystem exposes only the four
devices needed by the compiler. The subshell unmounts it when the build ends::

    (
        set -eu
        mount -t devfs devfs "$resolver_root/dev"
        trap 'status=$?; trap - EXIT; umount "$resolver_root/dev" || status=1; exit "$status"' EXIT
        trap 'exit 1' HUP INT TERM
        devfs -m "$resolver_root/dev" rule apply hide
        for device in null zero random urandom; do
            devfs -m "$resolver_root/dev" rule apply path "$device" unhide
        done
        env -i PATH=/sbin:/bin:/usr/sbin:/usr/bin LC_ALL=C TMPDIR=/work/tmp \
          chroot "$resolver_root" /bin/sh /work/recipe-inputs/build-freebsd-pkg-resolve.sh
    )

Use ``$resolver_root/work/freebsd-pkg-resolve`` as ``NATIVE_RESOLVER`` below.
Its required SHA256 is
``ad1be19a9491ac9b34c5a203c6c90d70907949c6ddb548a168034b64f8e87be9``.
The build preserves its sources and diagnostics. It does not install packages
or modify the host package database.

Prepare the mfsBSD image
------------------------

Build on a FreeBSD 15.1-RELEASE amd64 host as root. Install the build dependencies
required by the selected mfsBSD source revision. Copy the complete
``/opt/xcat/share/xcat/install/freebsd`` directory to the build host.

Obtain matching ``MANIFEST``, ``base.txz``, and ``kernel.txz`` files from the
FreeBSD release. Verify the release source and record the trusted SHA256 of
``MANIFEST`` before building. Select an exact mfsBSD Git commit, not a moving
branch name.

The legacy builder takes five arguments::

    sh freebsd/buildmfsbsd.sh MFSBSD_SOURCE DIST_DIRECTORY OUTPUT_ISO MFSBSD_COMMIT MANIFEST_SHA256

For a version 2 boot artifact, supply the native FreeBSD package archive and
resolver executable::

    sh freebsd/buildmfsbsd.sh --pkgbase PKG_ARCHIVE NATIVE_RESOLVER MFSBSD_SOURCE DIST_DIRECTORY OUTPUT_ISO MFSBSD_COMMIT MANIFEST_SHA256

The pkgbase build requires mfsBSD commit
``6e48fa48ebbb25953a7764a8f3cfda443fb9a768``. Supply the release
``pkg-2.6.2_1`` archive and the qualified FreeBSD native resolver. The resolver
links pkg 2.6.2 with the supplied ``patches/pkg-2.6.2-apply.patch`` corrections.
Staging verifies fixed checksums for both inputs. These FreeBSD build inputs
are separate from the Linux-native repository preparation tool.
The build stages them inside the RAM filesystem and emits the runtime manifest.
It does not include the operating-system package repositories in the boot artifact.

``MFSBSD_COMMIT`` is the full 40-character commit ID. ``MANIFEST_SHA256`` is the
64-character checksum. ``OUTPUT_ISO`` must not already exist. Build paths must
not contain spaces or shell metacharacters.

The builder verifies the release sets, adds the installation runtime, and
produces BIOS and UEFI boot media. It applies a checksum-pinned FreeBSD 15.1
installer cleanup correction for empty mount lists. An unexpected installer
source stops the build.

Copy the ISO to the installation owner and import it::

    copycds /path/to/xcat-mfsbsd.iso
    lsdef -t osimage

For legacy media, use the image name reported by ``copycds``. The default name
includes a media digest suffix. Imported legacy media resides below
``<installdir>/freebsd15.1/x86_64/<full-digest>``. Do not modify that directory.
Import a new bundle when the runtime or release payload changes.
For version 2 media, use the reported ``bootdir`` in a version 2 image
definition with the intended repositories and package lists.

Define installation policy
--------------------------

Import does not select a disk or an SSH key. Create a protected policy directory
on the installation owner, such as ``/etc/xcat/freebsd``. Policy files, public
key files, and their parent directories must be owned by root and must not be
writable by other users. Symlink paths are not accepted.

The image ``template`` attribute selects a key=value settings file. For example,
``/etc/xcat/freebsd/settings`` contains::

    authorized_keys_file=/etc/xcat/freebsd/administrators.pub

The public key file accepts plain OpenSSH keys, without authorized_keys options.
It does not accept private keys.

Create a disk policy for each node. For example,
``/etc/xcat/freebsd/node01.disk`` contains::

    target_disk=da0
    target_disk_ident=REPLACE_WITH_VERIFIED_DISK_SERIAL
    filesystem=zfs
    swap_size=0

Confirm the device name and serial on that node before using this policy. Do not
copy another node's disk identity. Valid device names use ``ada``, ``da``,
``nda``, ``nvd``, or ``vtbd`` followed by a number. ``filesystem`` accepts ``zfs``
or ``ufs``. ``swap_size`` accepts ``0`` or an integer followed by ``M`` or ``G``;
the default is ``0``.

Set the policy paths on the imported image::

    chdef -t osimage -o IMAGE_NAME template=/etc/xcat/freebsd/settings 'partitionfile=/etc/xcat/freebsd/#NODE#.disk'

``#NODE#`` expands to the xCAT node name. These files are not shell scripts and
do not use the Linux installation-template syntax.

Multi-disk ZFS policy
---------------------

Multi-disk installation accepts blank disks only. It rejects existing
partition tables, pools, other detected layouts, and ambiguous ownership.
This includes a previous successful installation and a partially completed
installation. There is no pool-GUID override or automatic destructive retry.
The single-disk policy above retains its existing reinstall behavior.

For a two-way mirror, use a disk policy such as::

    filesystem=zfs
    zfs_topology=mirror
    zfs_vdevs=da0@SERIAL_A,da1@SERIAL_B
    swap_mode=none
    swap_size=0

Replace each example serial with the verified hardware serial. Each member is
``device@serial``. Commas separate members within a group. Semicolons separate
mirror pairs for ``raid10``. Do not add whitespace or shell quoting inside
these values. Do not combine these fields with ``target_disk`` or
``target_disk_ident``.

.. list-table:: ZFS membership rules
   :header-rows: 1

   * - ``zfs_topology``
     - Required membership
   * - ``mirror``
     - One group of at least 2 members.
   * - ``raid10``
     - At least 2 groups, each containing exactly 2 members.
   * - ``raidz1``
     - One group of at least 3 members.
   * - ``raidz2``
     - One group of at least 4 members.
   * - ``raidz3``
     - One group of at least 5 members.

Every policy has at most 16 members. Device names and serials must be unique.
Serials accept letters, digits, underscores, periods, colons, plus signs and
hyphens, with a maximum of 128 characters. Unsupported serial representations
cause rejection. The installer does not guess an equivalent identity.

For four-disk striped mirrors, the membership can be::

    zfs_topology=raid10
    zfs_vdevs=da0@SERIAL_A,da1@SERIAL_B;da2@SERIAL_C,da3@SERIAL_D

Keep the other three fields from the mirror example. The pair boundaries are
part of the policy. Losing both members of one pair prevents root-pool access,
even when another pair remains intact. RAID-Z tolerates losses only within its
parity limit. Its boot loader still needs enough surviving pool members.

Redundant layouts require ``swap_mode=none`` and ``swap_size=0``. The runtime
uses one root pool and installs boot support on every selected member. UEFI
members receive both the FreeBSD loader and the standard fallback loader.
The ESP entry in the installed ``fstab`` uses ``noauto`` and a zero check pass.
Firmware disk selection and automatic fallback remain separate capabilities.
Verify both on the intended hardware before deployment.

The UEFI check requires one new boot entry for the first member, prepended to
the existing boot order. Existing boot entries and other captured boot variables
must remain unchanged. Firmware that rewrites them causes installation to fail,
even if the new entry appears usable. This can happen after the pool exists.
Retain the before/after firmware records and qualify this behavior on the target
hardware before deployment.

The installer checks identities and ownership before partitioning and at
later destructive boundaries. Keep selected hardware stable throughout
installation. A failure after partitioning starts can leave partial layouts.
It has no automatic rollback. Preserve the failure report and resolve the
disk contents explicitly before requesting another initial installation.

Use an image built with the current ``xcat-freebsd-install-4`` runtime.
Preparation rejects a multi-disk policy with an older boot runtime.
Disk replacement and pool expansion remain native administrative operations.
xCAT does not perform ongoing pool management.

Installed-node networking
--------------------------

Use ``confignetwork`` to configure the installed FreeBSD node from the ``nics``,
``networks`` and selected ``routes`` tables. It supports physical Ethernet
interfaces, VLANs, native LAGG failover or LACP, and bridges. These interfaces
can carry multiple static IPv4 and IPv6 addresses.

Provisioning still uses one IPv4 interface selected by MAC address. VLANs,
aggregation, bridges and IPv6 inside PXE or mfsBSD are outside this path.
DHCP, SLAAC, tunnels and switch configuration are outside this adapter.

Select the postscript before ``nodeset`` to configure networking after the
first disk boot::

    chdef node01 -p postscripts=confignetwork

For an installed node, apply the current table values with::

    updatenode node01 -P confignetwork

Use native FreeBSD interface names. Include every physical member in
``nictypes``. Put addresses on the LAGG or bridge, not its members. A VLAN
can use a physical interface or LAGG as its parent. A bridge can contain
physical interfaces, LAGGs or VLANs.

The adapter accepts these attributes:

.. list-table:: FreeBSD NIC attributes
   :header-rows: 1

   * - Attribute
     - Values
   * - ``nictypes``
     - ``Ethernet``, ``lagg`` or ``bond``, ``vlan``, and ``bridge``.
       Type names are case insensitive. Clones require ``laggN``, ``vlanN``
       or ``bridgeN`` names.
   * - ``nicdevices``
     - Pipe-separated member names. LAGG requires 2 to 16 physical members.
       A VLAN requires one parent. A bridge accepts 1 to 16 members.
   * - ``nicips``
     - Pipe-separated static addresses. Each address requires a matching
       ``nicnetworks`` entry. One network name can cover several addresses
       from the same subnet.
   * - ``nicnetworks``
     - Network names in address order. Use dotted IPv4 masks. For IPv6, use
       CIDR network notation and the matching prefix length in ``mask``.
       A leading slash in the mask is accepted.
   * - ``nicextraparams``
     - Space-separated options from the table below. Linux interface-file
       options and arbitrary ``ifconfig`` arguments are rejected.

.. list-table:: FreeBSD NIC options
   :header-rows: 1

   * - Option
     - Meaning
   * - ``MTU=NUMBER``
     - 576 through 9216, subject to the driver limit. IPv6 requires at least
       1280. Otherwise, use ``networks.mtu`` or inherit the parent MTU.
       Physical interfaces default to 1500. LAGG and bridge members require
       equal MTUs.
   * - ``LAGGPROTO=failover`` or ``LAGGPROTO=lacp``
     - Required for LAGG. Member order selects the failover primary.
       LACP requires a compatible peer or switch port channel.
   * - ``VLAN_TAG=NUMBER``
     - 1 through 4094. The default is the numeric suffix of the VLAN name.
   * - ``STP=yes`` or ``STP=no``
     - Enable or disable spanning tree on bridge members. The default is
       ``yes``. Allow forwarding convergence before checking data traffic.

For example, configure a physical interface with IPv4 and IPv6::

    mkdef -t network -o data4 net=192.0.2.0 mask=255.255.255.0
    mkdef -t network -o data6 net=2001:db8:1::/64 mask=/64
    chdef node01 nictypes.vtnet1=Ethernet \
        'nicips.vtnet1=192.0.2.10|2001:db8:1::10' \
        'nicnetworks.vtnet1=data4|data6'
    updatenode node01 -P confignetwork

To move those addresses onto a bridge over a VLAN over LACP, use::

    chdef node01 \
        'nictypes=vtnet1!Ethernet,vtnet2!Ethernet,lagg0!lagg,vlan100!vlan,bridge0!bridge' \
        'nicdevices=lagg0!vtnet1|vtnet2,vlan100!lagg0,bridge0!vlan100' \
        'nicips=bridge0!192.0.2.10|2001:db8:1::10' \
        'nicnetworks=bridge0!data4|data6' \
        'nicextraparams=lagg0!LAGGPROTO=lacp'
    updatenode node01 -P confignetwork

Additional interfaces do not replace the IPv4 default route. A configured
IPv6 network can supply ``networks.gateway``. IPv6 default gateways must agree.
A link-local IPv6 gateway receives the interface scope automatically.
The ``<xcatmaster>`` gateway token preserves the default selected during
installation. Set an explicit gateway to change it during management adoption.
When moving IPv6 management traffic, set the gateway on its new interface;
a retained link-local gateway cannot use an interface whose IPv6 is disabled.

Select static routes through ``noderes.routenames``. Each selected route needs
``net``, ``mask``, ``gateway`` and an explicitly configured ``ifname``. For
example::

    mkdef -t route -o storage4 net=203.0.113.0 mask=255.255.255.0 \
        gateway=192.0.2.1 ifname=bridge0
    mkdef -t route -o storage6 net=2001:db8:2::/64 mask=/64 \
        gateway=2001:db8:1::1 ifname=bridge0
    chdef node01 routenames=storage4,storage6

By default, the postscript preserves the installation interface. Use
``confignetwork -s`` to include it in the declared topology::

    updatenode node01 -P 'confignetwork -s'

The topology must retain the node's existing IPv4 address on the installation
interface or one of its descendants. Configure the corresponding switch ports
before migrating management traffic. Retain console access during the change.
Continue using ``-s`` for subsequent updates after adopting that interface.
The existing ``site.setinstallnic=1`` or ``yes`` setting also enables this mode.

The adapter validates the full plan before changing interfaces. It rejects
overlapping subnets, conflicting membership, unmanaged dependencies and missing
devices. It applies the plan in dependency order, reads back addresses and
routes, and checks the controller connection from the node's IPv4 address.
Only then does it save the managed block in ``/etc/rc.conf``. Verify traffic
on each data network separately.

An identical effective configuration is a no-op, including when unrelated
settings follow the managed block. Keep previously managed physical
interfaces in ``nictypes`` when updating. Clear their addresses to remove
Layer 3 configuration. Removing a managed clone from the definition destroys
that clone. The Linux ``-r`` option is not available on FreeBSD.

Network configuration must use ``/etc/rc.conf`` with
``network_interfaces=auto``. Existing unmanaged clones, manual routes on selected
interfaces, DHCP or SLAAC configuration, ``rc.conf.local`` and service-specific
network override files require manual integration. Route and clone list entries
that the saved plan does not own are retained, including additions made with
``sysrc``. Selected routes use ``xcat_net_NAME`` names; collisions with existing
route variables or list entries are rejected. Run custom network scripts as
separate postscripts.

A failed live change attempts to restore the prior configuration. The adapter
retains its last transaction under ``/var/db/xcat/network/last``. Execution
timeouts can interrupt rollback and require console recovery. An interrupted
or failed rollback leaves ``/var/db/xcat/network/pending`` and blocks another
attempt. Preserve that directory and inspect its logs before recovery. The
saved ``before.rc`` records the prior boot configuration. Use the console to
reconcile live and persistent settings before moving the retained transaction
aside and retrying.

Bootstrap, console and boot options
-----------------------------------

The settings file accepts ``bootstrap=dhcp`` or ``bootstrap=static``. DHCP is
the default. Static mode passes the node's address, netmask and gateway through
the loader handoff, so the installer can fetch its configuration without DHCP.
The preceding PXE/xNBA boot still needs the normal network-boot services.
Both modes configure the installed target with static network settings from
the xCAT database.

Set the serial console through the node's ``nodehm`` attributes::

    chdef node01 serialport=0 serialspeed=115200 serialflow=none

Ports ``0`` through ``3`` select COM1 through COM4. Supported speeds are
9600, 19200, 38400, 57600 and 115200. ``serialflow`` accepts ``none`` or ``hard``
for the installed login terminal.
Leave all three attributes empty when no serial console is required.
The runtime configures the loader, kernel UART and installed login terminal.
Server firmware and a remote-console service must use compatible settings.

Use native FreeBSD loader assignments in ``bootparams.addkcmdline``. Separate
assignments with spaces. An unprefixed assignment applies to the installer.
An ``R::`` assignment applies to the installed target's ``/boot/loader.conf``::

    chdef node01 addkcmdline='boot_verbose=YES kern.msgbufsize=1048576 R::kern.msgbufsize=262144'

This example gives the installer a 1 MiB message buffer and the target a
256 KiB buffer. Repeat an assignment in both forms when both phases need it.
Duplicate keys within one phase cause rejection. A boolean ``*_load`` or
supported ``boot_*`` option requires ``YES`` or ``NO``.

Values cannot contain spaces, quotes, shell substitutions or control characters.
Options that change the installer, root device, networking, console, kernel
path or executable loader directives are reserved. Configure those functions
through the installation policy and node attributes. Preparation rejects an
invalid option before arming the node.

These settings require a boot runtime with ``xcat-freebsd-install-3`` or later.
An older runtime accepts only the default DHCP mode without extra boot options
or a configured serial console.

Configure and install a node
----------------------------

Define the node address, MAC, and matching ``networks`` entry through the normal
xCAT configuration commands. Every enabled IPv4 ``networks`` entry must have a
valid, contiguous dotted-decimal mask, including entries for other subnets.
Exactly one network entry must match the node.
Configure a gateway in the node subnet if an installation endpoint is outside
that subnet.

Install ``xnba-undi`` on the provisioning owner, then run ``mknb x86_64``.
Debian installations that omit recommended packages can omit this bootloader.
Check that ``/tftpboot/xcat/xnba.kpxe`` and ``/tftpboot/xcat/xnba.efi`` exist before
booting a node.

Bind DHCP to the provisioning interface through ``site.dhcpinterfaces`` and
the DHCP service configuration. For Debian or Ubuntu ISC services, also check
``INTERFACESv4`` and leave ``INTERFACESv6`` empty when IPv6 DHCP is unused.
``makedhcp`` can rewrite ``/etc/default/isc-dhcp-server`` with the older
``INTERFACES`` setting. Keep required service overrides in a separate systemd
``EnvironmentFile``, then check the running DHCP process after regeneration.

Select xNBA and the provisioning MAC::

    chdef node01 netboot=xnba installnic=mac

The MAC table must identify one unambiguous provisioning MAC. If the node has
several eligible MAC addresses, set ``installnic`` to the desired colon-separated
MAC explicitly. Interface names such as ``em0`` are not accepted here.

For a service-node owner, set both attributes explicitly::

    chdef node01 servicenode=sn01 xcatmaster=sn01

The owner must have the imported bundle, policy files, and local DHCP/HTTP/TFTP
services. Retain the normal xCAT ``/install`` HTTP alias, including when
``site.installdir`` points to a different filesystem directory. HTTPS-only
distribution service is not supported by the initial runtime.

Prepare the installation, update DHCP, and boot the node::

    nodeset node01 osimage=IMAGE_NAME
    makedhcp node01
    rpower node01 boot

Do not boot the node if preparation or DHCP configuration reports an error.
On Kea, a rejected FreeBSD node retains its previous reservation and native
loader classes. Valid nodes in the same request can still be updated. A failed
``makedhcp`` update does not disable the old boot configuration. Correct the
reported input error and repeat the update before booting the node.
``bootparams.addkcmdline`` accepts supported FreeBSD loader assignments with
the current boot runtime. Linux kernel arguments are not valid FreeBSD options.
An invalid FreeBSD image detected during preflight stops a mixed-node request
before any installation image is prepared.

An explicit iSCSI server and target conflict with this installation path and
cause preparation to fail. Remove an obsolete SAN configuration only after
confirming that the node no longer uses it.

The installer verifies configuration, release sets, the provisioning interface,
and disk ownership before requesting permission to start. Imported ZFS pools,
attached GELI providers, and ambiguous existing storage cause a failure before
partitioning. Completion requires xCAT to select disk boot and acknowledge the
status update. A first-boot service reports that the installed system started.
It runs in the background, logs errors through syslog, and leaves reporting
pending after a timeout so that the next boot can retry.
The controller handles up to 64 FreeBSD status requests concurrently, with one
worker per node. The installer retries acknowledgments for about 15 minutes.
It does not reboot after installation without a completion acknowledgment.

Postscripts and boot reporting
------------------------------

During ``nodeset``, xCAT seals the selected scripts and their arguments for
the installation's first boot and later boots. The first boot runs the
selected ``postscripts`` and ``postbootscripts``. Later boots run only
``postbootscripts``, when the sealed ``site.runbootscripts`` policy enables
them. Changing a source script does not change a retained run. Use
``updatenode`` to select a new operation on an installed node.

Sealing includes the entire ``<installdir>/postscripts`` tree, including files
that the current selection does not execute. The sealed source has these
limits:

* 4,096 entries, including the root directory and selected template.
* 64 MiB of file contents in total, with at most 16 MiB per file.
* A 4 MiB manifest, paths of at most 4,096 bytes, and components of at most
  255 bytes. Directory depth and symbolic-link traversal are limited to 64.
* Owners must be root or the xCAT service account. Files and directories must
  not be writable by group or other users. Links must remain inside the tree;
  external hard-link aliases and link cycles are rejected.

Any violation prevents preparation, even when it affects an unselected file.
Keep unrelated archives and generated output outside the postscripts tree.

The ``xcatpostboot`` service reports the current boot in the background.
Its boot identity belongs to one kernel lifetime. A ``reboot -r`` reroot keeps
that identity and does not start a new boot-script cycle. Use a full reboot for
a new cycle. Run the worker and boot service in the installed system's root,
with a shared ``/var/run``; separate chroots or jails do not share its identity
lock. Reserve ``xcat.postscript.boot-id`` for xCAT. Do not set it in loader
configuration or change it with ``kenv`` while the system is running.
The controller binds its response to the installation generation, attempt,
boot and script run. A node's ``booted`` status alone does not establish
successful script execution. Check the run outcome and per-script results.
Results retain the arguments, exit status, standard output and standard error.
Each entry has a default execution timeout of 300 seconds. The package
prerequisite and script driver each have a 3,600-second execution timeout.
These execution deadlines are separate from the command's observation timeout.
On expiry, the supervisor sends TERM and CONT to its descendants, waits five
seconds, then sends KILL if needed. Cancelling the whole run, or a failure of
its outer capture supervisor, can also stop services started by earlier phases
of that run. Cancelling an individual phase can stop services that it started.

Each output stream retains at most 1 MiB. For a selection of more than 32
entries, each stream's limit is reduced to the integer part of 64 MiB divided
by twice the entry count. This bounds all retained entry output to 64 MiB.
Excess output is drained and discarded; it does not change the script's exit
status or prevent later entries from running. The report and command output
identify truncated streams and give their effective limit. These limits do
not restrict files that an administrator script creates.

A script may start a persistent service and return. The worker does not wait
for that service on normal completion. Services must detach or redirect their
standard output and error to their own files or the system logger. The worker
drains inherited output pipes for up to 100 milliseconds after the command
exits, then closes them. A later write to such a pipe can receive SIGPIPE or
EPIPE. The report flags streams that remained open when capture ended.

The node keeps run records under ``/var/db/xcat/postscripts`` and boot reports
under ``/var/db/xcat/boot-report``. The controller retains the collected report
at the location printed by ``updatenode``.

A delivery or reporting retry reuses the run identity. It does not execute
completed or uncertain scripts again. If reporting times out, its record
remains pending for a later retry. An interrupted run requires the explicit
recovery command described above. Do not remove run records to force a retry:
the controller checks that previously completed receipts remain on the node.

The controller stores postscript evidence under
``/var/lib/xcat/freebsd-postscripts``. Successful delivery polls remove their
temporary diagnostics after the transport returns. Boot polls retain one
observation per distinct state. Repeated observations reuse that evidence.
Terminal receipts, synchronization results and frozen script inputs remain
available for retries and diagnosis.

Package verification transfers full package manifests from verified archives.
It compares installed metadata, dependencies and archive provenance without
transferring the package file payload. Updates still transfer full archives.
After package work commits and script execution reaches a validated terminal
result, the node removes its package payload copies. The controller removes
its transfer archive after retaining that terminal receipt. This also applies
when a script fails or the framework records a terminal failure after successful
package work. Status, reports and retries remain available through the retained
records.

Active, uncertain and package-rejected runs retain their payloads. Missing
payload files alone cannot authorize cleanup. If the node reports that payload
retirement is pending, retry cleanup as root on that node::

    /usr/local/libexec/xcat-postscript retire RUN

Use the recorded 32-character run identity. This operation retries deletion
without repeating package work or scripts. A controller delivery retry also
finishes interrupted controller payload cleanup.

Successful release and report collection remove their temporary transport
directories after validating the response or publishing the report. Failed
transport attempts retain private ``.delivery-<RUN>.*``, ``.boot-<NODE>.*``,
``.release-<RUN>.*`` or ``.report-<RUN>.*`` directories. After resolving the failure, stop retry clients
and confirm that no status worker or transport uses the node. Archive the
failed attempt directories, verify the archive, then remove those directories
individually. Keep exports, synchronization directories and run records while
the installation or its retained reports depend on them.

Sealed sources and preparations can be shared by several nodes and runs.
There is no command to prune those shared records or the node's execution
history during an active installation. For decommissioning, stop the node and
its retry clients, then archive and verify its controller and node records.
Retire a complete controller store only after all installations that use it
are retired. Preserve the corresponding installation ownership records with
the archive. Removing a run record from an active installation can prevent
later observation and recovery.

Failure and retry
-----------------

Inspect the node console and xCAT status after a failed installation. Do not
assume that a failure after installation started left the target disk unchanged.

A repeated preparation with unchanged inputs reuses a prepared generation. An
installation that has started, is completing, or has failed cannot be rearmed
while it may still be running. Stop the node first, cancel the attempt, correct
the cause, and prepare a new installation. For a multi-disk policy, first
resolve any partial layout through an explicit administrative procedure.
Canceling the attempt does not erase disks or authorize reinstall::

    rpower node01 off
    nodeset node01 offline
    nodeset node01 osimage=IMAGE_NAME
    makedhcp node01
    rpower node01 boot

Installation ownership records reside in ``/var/lib/xcat/freebsd-install`` on
the selected owner. Do not remove these records to bypass an active attempt.
Stop the node before changing its installation owner.
Configuration and boot generations are retained for retry and diagnosis; they
are not automatically deleted after installation.

Physical hardware acceptance
----------------------------

Virtual-machine results do not qualify a physical server's firmware, storage
controller, disk identities, or removal behavior. Run this procedure on
authorized disposable disks before deploying a new hardware combination.
Keep physical acceptance marked ``NOT RUN`` until the observations are retained.

Record the server model, firmware revision, controller model and firmware,
disk models and serials, boot mode, xCAT candidate, and imported artifact hashes.
Record the selected policy and the identity of an unrelated sentinel disk.
Keep that disk outside every installation policy. Record its checksum before
and after the campaign.

Before installation, compare the physical disk inventory with the policy::

    geom disk list
    gpart list -a
    sysctl -n machdep.bootmethod

Select only the disposable disks. Do not erase an existing layout to make a
failed initial-install check pass. Resolve disk ownership and contents before
starting the campaign. Follow the server's removal procedure and controller
requirements when disconnecting members.

Use the normal ``nodeset``, DHCP preparation, and network-boot path. Retain the
complete firmware and installation console. After installation, detach its
media and make network boot unavailable. Boot from the installed disks.
Observe the running system directly::

    freebsd-version -k -u
    kenv -q smbios.system.uuid
    mount -p
    geom disk list
    gpart list -a
    swapinfo -h
    pkg-static -C /dev/null query -a '%n %v %a %k'

For ZFS, also capture the pool's current topology and errors::

    zpool status -g
    zpool status -LP
    zpool get guid,bootfs zroot

Check the current boot's postscript results and their controller receipts.
A retained ``booted`` status from a previous boot does not prove this boot.
Write test data, synchronize it, and retain its checksum outside the node.
Read and compare that data after every fault and recovery step.

For each firmware mode in use, perform the following storage checks:

.. list-table:: Physical storage campaign
   :header-rows: 1

   * - Layout
     - Required checks
   * - Single-disk UFS or ZFS
     - Initial installation, disk-only boot, and intentional single-disk reinstall.
       Check both zero swap and the intended nonzero swap configuration.
   * - Two-way mirror
     - Remove each member separately and boot from its survivor.
   * - Three-way mirror
     - Exercise all 3 single-member and all 3 two-member loss sets.
   * - Four-disk striped mirrors
     - Exercise all 4 single losses and all 4 losses of one member from each pair.
       Losing both members of one pair must prevent a usable root.
   * - RAID-Z1, 3 members
     - Exercise all 3 single losses and a loss beyond parity.
   * - RAID-Z2, 4 members
     - Exercise all 4 single losses, all 6 two-member losses, and a loss beyond parity.
   * - RAID-Z3, 5 members
     - Exercise all 5 single, 10 two-member, and 10 three-member loss sets.
       Also exercise a loss beyond parity.
   * - Wider layouts
     - Check the intended width and grouping, including a wider RAID-Z group
       and six-disk striped mirrors when these are deployed.

Start each independent fault case from a healthy restored baseline. For every
recoverable loss set, select each surviving boot-capable member in turn.
Keep the other members needed by the root pool connected. Record the disk
actually selected by firmware and verify the mounted root and data.

Test automatic fallback separately by removing the preferred boot member
without selecting another member manually. For UEFI, retain the original
NVRAM state and also test the standard fallback loader with fresh firmware state.
Capture ``efibootmgr -v`` and the actual loader device. Do not infer automatic
fallback from a successful manual selection.

Test live member loss during synchronized, acknowledged writes separately
from cold degraded boot. Check every acknowledged record after recovery.
Replace a failed member through the native administrative procedure, wait
for resilvering to finish, and restore its bootcode or ESP contents.
Check the recovered data and boot from the replacement disk. For a topology
that needs other members, keep the required surviving members connected.

Retain the console, current boot identity, disk and pool inventory, data hashes,
package roster, per-script results, and outcome for each case. Record a missing
case as ``NOT RUN``. After the campaign, remove temporary resources and restore
the intended firmware boot order.
