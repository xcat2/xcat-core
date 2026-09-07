FreeBSD repository inspection
=============================

``xCAT::FreeBSDRepo`` provides read-only inspection helpers for FreeBSD
15.1-RELEASE amd64 repositories. These helpers do not import an image, publish
a repository, select an installation package list, or install packages.
The existing mfsBSD bundle importer does not yet use this interface.

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

Behavioral validation
----------------------

The native integration test builds disposable package archives and signed
catalogues without installing them. It requires OpenSSL, GNU tar and cp,
Zstandard support, and the preparation tool. Run it explicitly::

    XCAT_FREEBSD_NATIVE_PKG=/absolute/path/to/pkg \
    XCAT_FREEBSD_NATIVE_LIBDIR=/absolute/path/to/private/lib \
    PERL5LIB=perl-xCAT:xCAT-server/lib/perl \
        prove -v xCAT-test/unit/freebsd_repo_native.t

Omit ``XCAT_FREEBSD_NATIVE_LIBDIR`` when the executable needs no private library
directory. Without ``XCAT_FREEBSD_NATIVE_PKG``, the integration test skips;
that skip is not native repository validation. Release-media validation must
also check every archive in actual disc1 and DVD trees. Neither test establishes
``copycds`` publication, target package installation, or physical-hardware
acceptance.
