FreeBSD repository preparation
==============================

``xCAT::FreeBSDRepo`` provides read-only inspection helpers for FreeBSD
15.1-RELEASE amd64 repositories. These helpers do not import an image, publish
a repository, select an installation package list, or install packages.
``xCAT::FreeBSDRepoImport`` adds immutable repository publication after native
inspection. Neither interface is connected to ``copycds`` or image registration
yet. The existing mfsBSD bundle importer remains separate.

Trust and execution boundary
----------------------------

Run inspection in a trusted Linux preparation environment with ``pkg`` 2.8.2
and ``/usr/bin/tar`` with Zstandard support. The caller supplies the absolute
native executable path and its trusted SHA256. An optional private library
directory requires its complete ``snapshot_tree`` digest. Inspection checks
these identities before and after native execution. Tool delivery and system
library qualification are separate requirements.

Inputs must remain immutable during inspection. The helper detects ordinary
source changes, but filesystem rechecks do not provide an atomic snapshot
against a hostile writer. An importer must stage private, immutable inputs,
validate them, and verify the published result.

Native commands use private configuration, repository, database and cache
directories. They receive a replacement environment and no interactive input.
Only local catalogue URLs are configured. Repository auto-update, plugins,
triggers and service-script handling are disabled. Each command has a
60-second deadline and bounded output. Inspection does not run package
installation scripts or use the host package database. This process isolation
is not an operating-system sandbox.

The qualified native pkg tool requires root-owned private databases. Run the
native integration checks as root inside an isolated preparation environment.
Do not mount a management node's package database into that environment.

Generic repository interface
-----------------------------

Call ``inspect_repository($root, %options)`` with these options:

* ``tool``: a hash containing ``path`` and ``sha256``. If private libraries are
  needed, also supply ``library_directory`` and ``library_digest``.
* ``catalogue_prefix``: an optional relative directory below the repository
  root, such as ``FreeBSD:15:amd64``. The default is the root directory.
* ``trust``: one of the explicit policies below.

The ``pubkey`` trust policy contains ``type => 'pubkey'``, the absolute public
key ``path``, and its trusted ``sha256``. Native pkg must authenticate both
catalogue formats separately. A successful ``pkg update`` exit alone is not
accepted; a fresh native query must also succeed.

The ``operator-trusted-tree`` policy contains its ``type`` and the trusted
repository snapshot ``digest``. It permits unsigned catalogues whose exact
tree the operator has accepted. It does not manufacture an upstream signature.
Computing a digest from untrusted input and accepting that same digest is not
provenance verification. Fingerprint-directory policies are not implemented.

The supported catalogue profile is deliberately narrow:

* ``meta.conf`` uses the native writer's flat assignments with metadata version
  2, ``packing_format = "tzst"``, ``data = "data"``,
  ``manifests = "packagesite.yaml"``, and
  ``manifests_archive = "packagesite"``. Both file-list keys must use
  ``files``, ``filesite``, or ``filesite.yaml``. Other keys, directives,
  duplicate keys and non-assignment syntax are rejected. If ``meta`` exists,
  its parsed values must agree with ``meta.conf``.
* Both ``data.pkg`` and ``packagesite.pkg`` are required. The former contains a
  JSON ``data`` member; the latter contains newline-delimited JSON in
  ``packagesite.yaml``. Catalogue input and native output are bounded to
  64 MiB, JSON nesting to 32 levels, and the package population to 100,000.
* The data object contains ``packages`` and empty ``groups`` and
  ``expired_packages`` arrays. Complete original package records must agree
  across both formats, including fields omitted by native raw query output.
  Duplicate package identities are rejected.
* Native queries of the two isolated catalogue formats must agree and contain
  the same package identities as the original records.
* Every package archive must exist inside the snapshot, match its catalogue
  size, pass native checksum verification, and contain matching embedded
  metadata. The repository-added ``path``, ``repopath``, ``pkgsize`` and
  ``sum`` fields are checked separately. Unlisted regular ``.pkg`` archives
  are rejected. Valid relative archive and directory aliases are retained.

The target ABI is ``FreeBSD:15:amd64`` and OSVERSION is ``1501000``. The
supported package ABI spellings are ``FreeBSD:15:amd64``, ``FreeBSD:15:*``,
``FreeBSD:15``, ``FreeBSD:*`` and ``FreeBSD``, without case sensitivity.
Other native wildcard expressions are not implemented. An optional
``FreeBSD_version`` annotation must be a positive integer no greater than
``1501000``. Application packages need not have the exact base OSVERSION.

The result has format ``xcat-freebsd-repository-1``. It contains the source
tree, portable trust and tool identities, complete package records, validated
archive identities, metadata, and a canonical content digest. Package map keys
join name, version, origin and ABI with NUL separators. The result sets
``native_validated=1`` and ``selection_validated=0``. The nested tree snapshot
still has ``native_validated=0`` because a tree hash alone proves no native
package semantics.

Release interface and DVD bootstrap
-----------------------------------

Call ``inspect_release($root, tool => $tool, trust => $trust)`` for extracted
release media. The trust policy is ``operator-trusted-release`` with a trusted
``inspect_release_tree`` digest. That digest covers the selected release
identity files and repository trees, not every file on the ISO. ISO provenance
verification belongs to the caller. Unrelated media returns no result.

The base repository is ``usr/freebsd-packages/offline``. Optional DVD
applications are below ``packages/FreeBSD:15:amd64``. All supplied repositories
are validated. Base ``FreeBSD-*`` packages must have version ``15.1``, origin
``base/<name>``, the exact target ABI and OSVERSION. The runtime, generic
kernel, minimal-set and base-set packages are required. Each release repository
must contain exactly one target-ABI ``ports-mgmt/pkg`` bootstrap package;
its version is independent of the FreeBSD release version.

Some 15.1 DVD media contain a dangling ``Latest/pkg.pkg`` link targeting
``../All/pkg-2.6.2_1.pkg`` although the archive is under ``All/Hashed``.
Only this known release-specific exception is permitted. Inspection returns a
repair descriptor bound to the uniquely validated application bootstrap path
and SHA256. It does not alter the media or substitute the base repository's
package with the same name and version. An existing bootstrap alias must
resolve to the selected bootstrap archive.

The result has format ``xcat-freebsd-release-1`` and retains separate base and
application descriptors, bootstrap identities, and proposed link repairs.
``selection_validated`` remains zero. A later native dependency-selection step
must verify the requested package closure before any target disk write.

Immutable publication
---------------------

Call ``xCAT::FreeBSDRepoImport::import_repository($source, $installroot,
%options)`` or ``import_release($source, $installroot, %options)``. Both accept
the inspection options above and an optional ``nonoverwrite`` boolean.
Release imports do not accept ``catalogue_prefix``. Unknown or duplicate
options are errors. The importer performs native inspection itself; it does
not accept a caller-supplied validation flag or descriptor.

The source and install root must be absolute, existing directories. The source
root cannot be a symlink. The install root and publication parents must be
caller-owned and not group- or other-writable. Ancestors must be real directories
owned by root or the caller. Sticky shared temporary ancestors are permitted.
Keep source contents and publication parents under caller control throughout
the operation. These checks do not isolate the importer from a hostile root
process or provide an atomic filesystem snapshot.

Publication uses this layout::

    <installroot>/freebsd15.1/x86_64/repositories/<import-digest>/
        manifest.json
        base/                 # release pkgbase repository
        applications/         # optional complete DVD repository

A generic import contains ``repository/`` instead of the release roles. Public-
key imports also contain the validated key as ``repository.pub``. Importing
the complete application repository does not select or install its packages.

The manifest format is ``xcat-freebsd-repo-import-1``. It records the complete
native source descriptor, each derived repository snapshot, applied link
repairs, and copied trust-file identities. It retains ``native_validated=1``
and ``selection_validated=0``. The manifest digest excludes its own digest
field and identifies the canonical JSON content. Source, destination and tool
paths are not part of that identity. Different trust or preparation-tool
provenance produces a separate import even when package bytes match.

The importer copies snapshotted entries into a private staging directory.
It verifies the complete result against the expected entries before rename.
The known DVD bootstrap repair changes only its validated relative link.
The original source descriptor and repaired tree identity remain distinct.
Other links, catalogues and archive bytes are preserved. Source media are not
modified.

Published files are caller-owned, have independent inodes, and use mode 0444.
Published directories use mode 0555. Source regular-file timestamps must be
positive and are preserved on initial publication. Reuse requires positive
timestamps, but does not replace them with timestamps from a relocated source.
The aggregate publication is limited to 100,000 entries and 1 TiB, including
wrappers and the manifest. The manifest has a 512 MiB limit.

A stable, empty mode-0600 lock serializes publication. The lock must be a
caller-owned regular file with one link. A busy lock causes an immediate error;
the caller may retry after the active import finishes. An existing destination
is fully checked for content, links, permissions, ownership and file metadata.
An identical import is reused without rewriting it. ``nonoverwrite=1`` instead
rejects any existing destination. A changed destination is never replaced.

On failure, the importer removes only its private staging directory. Existing
publications remain in place. Cleanup failures are included in the error.
Rename provides atomic visibility, not a power-loss durability guarantee.
Successful results add ``path`` and ``reused`` fields; these runtime fields are
not stored in the manifest. Repeat import still requires the original source
contents and the explicit trust/tool policy.

Behavioral validation
----------------------

The native integration test builds disposable package archives and signed
catalogues without installing them. It requires OpenSSL, GNU tar and cp,
Zstandard support, and the preparation tool. Run it explicitly::

    XCAT_FREEBSD_NATIVE_PKG=/absolute/path/to/pkg \
    XCAT_FREEBSD_NATIVE_LIBDIR=/absolute/path/to/private/lib \
    PERL5LIB=perl-xCAT:xCAT-server/lib/perl \
        prove -v xCAT-test/unit/freebsd_repo_native.t \
            xCAT-test/unit/freebsd_repo_import.t

Omit ``XCAT_FREEBSD_NATIVE_LIBDIR`` when the executable needs no private library
directory. Without ``XCAT_FREEBSD_NATIVE_PKG``, the integration test skips;
that skip is not native repository validation. The import test also requires
Linux and root for its native database and ownership fixtures. It exercises
real native inspection and injects failures only at filesystem boundaries.
Release-media validation must also check publication and every archive in
actual disc1 and DVD trees. Neither test establishes
``copycds`` publication, target package installation, or physical-hardware
acceptance.
