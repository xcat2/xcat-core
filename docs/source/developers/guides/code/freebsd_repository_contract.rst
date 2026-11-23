FreeBSD repository preparation
==============================

``xCAT::FreeBSDRepo`` provides read-only inspection helpers for FreeBSD
15.1-RELEASE amd64 repositories. These helpers do not import an image, publish
a repository, select an installation package list, or install packages.
``xCAT::FreeBSDRepoImport`` adds immutable repository publication after native
inspection. The FreeBSD ``copycds`` plugin imports approved release repositories
and registers version 2 image metadata. ``freebsdrepo inspect`` and
``freebsdrepo import`` inspect and publish supplemental repositories without
changing image definitions. These paths do not select packages or enable
version 2 installation. The existing mfsBSD bundle importer remains separate.

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

Reading an existing publication
-------------------------------

Call ``xCAT::FreeBSDRepoImport::inspect_import($publication, $installroot)``
to verify a publication without its original media or preparation tool.
The publication must use the exact digest-based layout above. Both paths must
meet the publication ownership and ancestor rules. The install root may have
moved; source paths are not needed.

The reader checks the bounded, canonical manifest, its nested digests, release
identity, tool and trust records, package-to-archive inventory, and source-derived
repository trees. Release bootstrap and link-repair records must agree with the
shared release rules. Every published entry is then checked for content, links,
ownership, permissions and required file metadata. Missing, changed or extra
entries are errors.

The result is the stored manifest with its current ``path``. It has no ``reused``
field. Reading does not create or acquire the import lock, create a cache,
execute native commands, or alter the publication. The original media may be
removed after a successful import.

This check verifies a caller-controlled publication and its recorded evidence.
It does not authenticate a newly supplied repository, repeat native signature
verification, or establish dependency closure. A caller who controls the entire
publication can replace its content and evidence together; the digest is not
an independent signature. Use the import interfaces for new repository content.
``selection_validated`` remains zero after readback.

Package planning diagnostics
----------------------------

``freebsdrepo plan IMAGE --diagnostics`` requires authenticated xCAT root.
The plugin checks the server-set ``_xcat_authname`` before reading image rows,
policy, lists or repositories. It requires exactly one string equal to
``root``. The daemon UID and request-supplied ``username`` confer no authority.
The option is invalid for inspection and import.

``xCAT::FreeBSDPackagePlan::resolve`` and ``resolve_image`` accept an optional
``diagnostics => \$bytes`` argument. It must reference an undefined scalar
before protected reads. Trusted in-process callers own authorization.
Ordinary calls omit the argument.

On a supported planning failure, the plugin adds one ``DIAGNOSTICS:`` data
item containing canonical ASCII JSON. The normal client sends it to standard
output and preserves the original standard error and nonzero exit status.
No report appears on success or before complete import validation.
The option does not change successful plan bytes or publication behavior.

The JSON object has exactly four fields: ``format``, ``scope``, ``status``
and ``records``. The format is ``xcat-freebsd-package-diagnostics-1``.
Record fields depend on scope:

* ``requested-selection``: ``kind``, ``selection`` and ``name``.
  The kind is ``missing-component``, ``missing-application`` or
  ``application-not-selected``. The selection index is 1-based and the name
  is the exact validated input.
* ``imported-catalogue-name-references``: ``kind``, ``repository``,
  ``package`` and ``dependency``. The kind is
  ``unavailable-dependency-name``. Repository fields are ``id``,
  ``publication`` and ``role``. Package fields are ``name``, ``version``,
  ``origin`` and ``abi``.

Catalogue facts describe authenticated imported records, including unselected
packages. Each dependency name lacks an exact, case-sensitive match among
the imported base and application package names. The scan ignores versions,
origins, ABIs and provider capabilities. A same-name package suppresses this
fact but does not prove dependency satisfaction. Repository identities describe
the observed attempt, not subsequent filesystem state. Native resolution
remains the authority for planning success.

Catalogue records follow repository order, package identity order, then
dependency name order. Limits are 64 records, 65,536 encoded bytes per record,
and 262,144 encoded bytes per report, excluding the ``DIAGNOSTICS:`` prefix.
The collector reserves one byte for the longer ``truncated`` status.
JSON escaping preserves decoded names, including non-ASCII characters.

``complete`` means the scoped scan completed, not that it diagnosed the
native failure. ``truncated`` retains the deterministic prefix before the
first count or byte limit. ``unavailable`` has an empty ``records`` array
when metadata or collection prevents a report. Collector failure never
replaces the original planning error.

Reports expose protected names only through the opted-in interface. They do
not copy raw native stderr, exception text, request environments or complete
manifests. The collector reads no additional repositories and does not retry
resolution. It does not publish diagnostic files or alter imported content.

Installer command budgets
-------------------------

Package preparation has a 30-minute budget. Installation has a 60-minute
budget. Both use the required native ``xcat-postscript-time uptime`` helper,
so wall-clock corrections do not change the remaining time. Each command
receives the smaller of its own timeout and the remaining operation budget.
Timer reads have a separate 5-second timeout. Failed, malformed or regressing
readings stop the operation without a wall-clock fallback.

Installed verification inputs
-----------------------------

Postscript verification uses ``xcat-freebsd-local-manifests-1``. Each package
row retains the original archive fields and adds the full ``+MANIFEST`` size
and SHA256. The controller extracts that member from the verified archive.
The native helper parses those same bytes through pkg's manifest parser and
keeps the full metadata and dependency comparisons used for archive inputs.
Each manifest is limited to 128 MiB, with a 512 MiB total. Installation,
update, preflight and prior managed requests reject this verify-only format.
Managed output retains the original archive provenance format.

``managed.request`` combines the current selection with previously managed
packages that remain installed. Its ``plan`` header identifies the latest
operation. Retained rows can carry repository IDs, repository paths and archive
paths from older plans; the header does not reinterpret those fields against
the latest repository list. Retained rows must match the installed package's
name, version, origin and ABI. A selected package already at the requested
version must also match the prior archive SHA256 and current package metadata.
Source paths are historical annotations and must not authorize fetching or
installation. A later operation resolves its own plan and verifies its current
inputs. The previous operation's durable receipt binds the complete managed
request before reuse.

Payload retirement requires a committed terminal receipt. The node binds its
retirement record to the snapshot, request, package head and terminal result.
The controller binds its retirement record to the export manifest and retained
terminal receipt. Each record is durable before deletion starts. Readers use
that proof to accept payload absence while preserving status, reports and
same-run retries. Framework failure results also permit retirement when their
completed package receipt and committed head match the terminal result. Active,
uncertain and package-rejected runs retain inputs.

Interrupted package provenance
------------------------------

Explicit release holds the node lock and requires either a different boot or
the complete same-boot observations described below. Native apply starts only
after the action record and its
directory are synced. When that record is absent, or a valid native rejection
proves apply never started, the worker retains the previous package head.
``packages.preserved`` binds that disposition to the run, snapshot, plan,
installation anchor and previous head. A native rejection also binds its
receipt digest. Earlier torn start or roster records do not prevent this
no-apply disposition. The original execution remains uncertain.

Otherwise, the worker invokes ``local-recover``. It validates the installation
anchor, admitted snapshot, request,
configuration and previous package head before invoking the pinned helper.
Recovery uses a fresh, empty ``recovery.XXXXXXXX`` directory below the original
package workspace. Capture writes outside that directory until the helper exits.

The helper compares the installed roster with the retained ``before`` roster,
previous managed request and original request. Unchanged managed identities keep
their archive provenance. Nonempty operations can exclude prior identities that
were already missing or different in the original ``before`` roster. Each
drifted prior identity is logged, including identities re-added by the operation.
This requires a valid action record and no native
rejection. Empty requests and operations without that authorization remain strict.
Captured diagnostics can be truncated. The receipt-bound prior request and
``before`` roster retain the complete evidence for which prior identities were
already absent or different; the diagnostic text is not authorization.
Compare the prior request with the managed output to identify final exclusions.
Changed identities take provenance from the current request's archive, including
when an older prior record names the same identity with a different archive.
Changed identities require an original update scope,
no native rejection, matching archives and a complete action plan. Verify-only
requests cannot authorize changed identities. Recovery does not adopt unchanged
unmanaged packages, apply package jobs, execute triggers or repeat scripts.
Unexplained package changes, missing packages, pending triggers and invalid
records stop recovery. If actions exist and no valid rejection proves apply
never started, torn records require restoration of verified evidence or a
consistent system backup. They cannot be reconstructed from the installed
package identities alone.

``xcat-freebsd-local-recover-1`` binds the request, previous request, native start,
before and observed rosters, managed output, action plan and rejection record.
An absent action or rejection record uses ``-`` as its digest. The receipt
records ``scope=provenance-only`` and ``execution=uncertain``. Its completion
field describes reconciliation only. It does not establish payload integrity,
package-script completion or compatibility of a partially upgraded system.

The helper and worker limit each installed roster to 128 MiB. This includes
dependency rows. Request and managed-request records keep their 8 MiB limit.

The worker requires an observed helper exit of zero and closed capture streams.
A native receipt alone cannot authorize publication. The separate
``packages.recovered`` record binds the native receipt, capture and retained
inputs. A version 2 package head identifies that record. Future operations
validate the recovered head before using its managed request. Ordinary completed
operations retain the version 1 head format.

Package completion and recovery records are finished in private staging directories
before atomic publication. Recovery retries preserve earlier attempts and can
finish an interrupted head or release publication. Collected reports retain
recovery evidence while reporting the original run as uncertain. Later
operations cannot complete its unfinished script entries.

Supervised execution and release
--------------------------------

New postscript runs bind the started record and native timer digest in a
supervision record. Each guarded capture records its paths, bounds and start
before executing a command. Its completion record binds the native observation
and log digests. The capture supervisor retains the node lock until it observes
the direct command; administrator scripts do not inherit that lock. Detached
services may remain alive after their starting script completes.

The outer framework observer has no independent deadline. Package and driver
phases retain their separate deadlines, and each script keeps its entry limit.
This avoids shortening the combined execution budget. Framework output remains
bounded and is retained separately from script and package output.

Same-boot release requires a fresh exclusive node lock, an unchanged timer,
and complete capture observations. Package captures must also report closed
streams. The process-state query must identify the original worker as absent,
zombie, or replaced by a different process identity. Query errors and malformed
responses refuse release. This query is only authoritative for the original
worker, which keeps the observer's host-root credentials and visibility. It is
not an absence test for services that change credentials or enter a jail.
The reported running state includes stopped and exiting processes.

Version 2 release records bind the original start, supervision record, process
observation and capture inventory. Historical collection validates those
retained observations, without querying a later process or package head. They
are producer records, not independent kernel attestations. Version 1 release
records continue to require a different boot. Neither format changes uncertain
script execution into success.

An observed framework failure can publish a version 3 terminal result after
completed package evidence and the full capture inventory validate under a
fresh node lock. Its immutable snapshot retains the entry dispositions,
package proof, phase records and bounded diagnostics. The worker syncs that
snapshot before publishing the separate terminal receipt. Version 4 evidence
archives export these retained contents. A script without a completed entry
record has no invented exit status, even though the framework outcome is
terminal and failed. If a command observation or package proof is missing,
the run remains uncertain. A failed terminal publication likewise cannot
authorize cached terminal reporting or payload retirement.

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
