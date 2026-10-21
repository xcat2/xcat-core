#############
freebsdrepo.8
#############


****
NAME
****


\ **freebsdrepo**\  - Imports offline FreeBSD repositories and plans package selections.


********
SYNOPSIS
********


\ **freebsdrepo inspect**\  \ */absolute/tree*\

\ **freebsdrepo import**\  \ */absolute/tree*\  \ **-**\ **-policy**\  \ *profile*\  [\ **-w**\ ]

\ **freebsdrepo plan**\  \ *osimage*\  [\ **-**\ **-diagnostics**\ ]

\ **freebsdrepo**\  [\ **-h | -**\ **-help**\ ]


***********
DESCRIPTION
***********


\ **freebsdrepo**\  imports supplemental binary-package repositories for FreeBSD
15.1-RELEASE amd64 targets. The source must be a complete repository directory
on the management node. The command does not copy files from the client,
mount an ISO, or remove the source. Use \ **copycds**\  for release media.

Restrict \ **freebsdrepo**\  access to trusted administrators through the xCAT
policy table. Inspection reads source files with the management daemon's
privileges, even though it does not change repository content.

\ **inspect**\  reports \ ``TREE_DIGEST``\  and \ ``BYTES``\  for the source tree. It does not
read the import policy, run the native package tool, publish files, or change
image definitions. Inspection alone does not authenticate a repository or
establish package compatibility.

\ **import**\  selects one named profile from the protected JSON policy identified
by \ ``site.freebsdimportpolicy``\ . The policy pins the prepared Linux-native
\ ``pkg``\  2.8.2 executable, optional library directory, and repository trust.
The command does not install this preparation tool.

An import validates native catalogues, archive identities and target metadata
before publishing beneath the configured installation directory. It uses
private package databases and caches. It does not install FreeBSD packages into
the management node or fall back to public repositories.

The command reports an immutable publication path and its \ ``repository``\  role.
Use that role as an explicit \ ``otherpkgdir``\  reference in a version 2 FreeBSD
image. Import does not change image definitions, select packages, or validate
the dependency closure of an image's package lists. It does not replace the
image's base repository or mfsBSD boot artifact.

An ordinary repeat import verifies and reuses an unchanged publication.
Changed or corrupt published content is rejected, not overwritten.

\ **plan**\  reads one existing FreeBSD 15.1-RELEASE amd64 installation image with
\ ``imageversion=2``\ . It requires an imported base role in \ ``pkgdir``\  and one or
more protected component-list files in \ ``pkglist``\ . It reads supplemental
roles from \ ``otherpkgdir``\  and application-list files from \ ``otherpkglist``\  in
their configured order. Disabled or duplicate image rows are rejected.

Planning uses the policy's pinned native solver and verified imported
catalogues to resolve the complete dependency closure. It publishes a
read-only file under \ ``<installdir>/freebsd15.1/x86_64/plans/<sha256>.plan``\
and reports \ ``Package plan:``\  and \ ``SHA256:``\ . Repeating the same selection
verifies and reuses the same file. A plan pins package identities, repository
provenance and archive checksums; it does not copy another set of archives.

Planning does not require \ ``bootdir``\ , a template or a disk policy. It does not
change image definitions, arm nodes, install packages or enable version 2
deployment. No public repository is used as a fallback.


*******
OPTIONS
*******



\ **-**\ **-policy**\  \ *profile*\

 Select one repository profile from \ ``site.freebsdimportpolicy``\ . Required
 exactly once for \ **import**\  and not accepted by \ **inspect**\  or \ **plan**\ .



\ **-w**\

 Reject an existing publication. Accepted only by \ **import**\ .



\ **-**\ **-diagnostics**\

 Request failure details for \ **plan**\ . The authenticated xCAT user must be
 \ ``root``\ . The daemon's user ID does not grant access to this option.
 Not accepted by \ **inspect**\  or \ **import**\ .



\ **-h | -**\ **-help**\

 Display command usage without inspecting or importing a repository.




******
POLICY
******


The policy format is \ ``xcat-freebsd-import-policy-1``\ . It has \ ``tool``\ ,
\ ``releases``\  and \ ``repositories``\  objects. A supplemental profile is a member
of \ ``repositories``\ . Signed repositories use a pinned public key, for example:


.. code-block:: perl

  "extra": {
    "trust": {
      "type": "pubkey",
      "path": "/etc/xcat/keys/freebsd-extra.pub",
      "sha256": "<public-key-sha256>"
    },
    "catalogue_prefix": ""
  }


Replace the placeholder with the authenticated key's SHA256. An empty
\ ``catalogue_prefix``\  selects catalogues at the source root. A nested catalogue
requires an explicit relative prefix in the profile.

An unsigned repository requires explicit operator approval. Its profile uses
\ ``"trust": {"type": "operator-trusted-tree", "digest": "<tree-digest>"}``\ .
Authenticate the source before approving the digest reported by \ **inspect**\ .
Inspection does not create or update approvals.

All digests contain 64 lowercase hexadecimal characters. The policy must be
a nonsymlink regular file, no larger than 1 MiB, with one link and protected
ancestors. It must be owned by root or the importing user and must not be
writable by group or others. Refer to the FreeBSD administrator guide for
the complete policy and native preparation-tool requirements.

Poudriere output is one possible repository source. Poudriere is not required.
The repository must include the archives needed for the intended deployment.

Planning additionally requires a \ ``solver``\  object with \ ``path``\  and \ ``sha256``\
fields. Its path identifies the prepared Linux-native \ ``freebsd-pkg-resolve``\
executable. The digest pins that executable. The solver must use the pinned
\ ``pkg``\  2.8.2 libraries. Planning requires the tool's \ ``library_directory``\  and
\ ``library_digest``\  fields and binutils \ ``/usr/bin/readelf``\ . Executables,
libraries and their ancestors must be protected from non-owner writes.
Library search paths must stay within the pinned directory.
Import operations do not require \ ``solver``\ . The administrator guide gives
the source and build procedure.


*************
PACKAGE LISTS
*************


Each file contains UTF-8 text with LF line endings. A nonempty file must end
with LF. Blank lines and comments beginning with \ ``#``\ , optionally preceded
by spaces or tabs, are ignored. Other lines are literal component or package
names: spaces are not trimmed and commas do not separate names. Dynamic
\ ``#INCLUDE``\ , \ ``#INCLUDE_\*``\ , \ ``#ENV``\  and \ ``#NEW_INSTALL_LIST``\  directives are
rejected without regard to case. Ordinary errors do not echo list contents.

\ ``pkglist``\  selects native base components, such as \ ``base``\ . An empty file
selects only the mandatory minimal-system, kernel and package-manager roots
and their dependencies. \ ``otherpkglist``\  selects application package names;
it is optional. Duplicate names and repeated source paths are rejected.
\ ``kernel-dbg``\  requires a kernel debug package. \ ``debug``\  adds available debug
packages for selected base sets. Sets such as \ ``src``\  and \ ``tests``\  need no
debug counterpart.

List files have the same ownership, link and permission restrictions as the
policy. Limits are 64 files per list attribute, 1 MiB per file, 8 MiB across
both attributes and 8192 explicit roots. The expanded native request is also
limited to 8192 package roots, including mandatory and component roots.
The resolved closure is limited to 8192 packages. The serialized plan is
limited to 16384 records and 8 MiB. Exceeding these limits stops resolution
or plan publication.
An image can reference at most 32 repository roles, including its base role.

Earlier application repositories take priority for explicit roots. Native
dependency resolution can select a dependency from its parent's repository
instead of an earlier provider. The plan records every selected provider.


***********
DIAGNOSTICS
***********


With \ **-**\ **-diagnostics**\ , a planning failure may add \ ``DIAGNOSTICS:``\  followed by
one JSON object to standard output. The original standard error and nonzero
exit status remain unchanged. No plan is published on failure. Successful
output and plan contents remain unchanged, with no diagnostic report.

The report can identify an unavailable requested name or list dependency
names absent from the verified imported catalogues. Catalogue records can
include unselected packages. They are name-reference facts, not an explanation
of the native solver failure or a proposed dependency closure.

\ ``status``\  is \ ``complete``\ , \ ``truncated``\ , or \ ``unavailable``\ . A complete report
covers its stated scope, not every cause of failure. Truncation retains the
ordered prefix within the count and byte limits. An unavailable report has no
records because diagnostic collection failed. Limits are 64 records, 65,536
encoded bytes per record, and 262,144 bytes for the JSON report.

The report contains names from protected package lists and catalogues.
Protect captured output accordingly. It does not include raw native errors
or complete list contents. Without this option, ordinary output is unchanged.


********
EXAMPLES
********


Inspect a repository already copied to the management node:


.. code-block:: perl

  freebsdrepo inspect /srv/offline/freebsd-extra


After authenticating the source and configuring the \ ``extra``\  policy profile:


.. code-block:: perl

  freebsdrepo import /srv/offline/freebsd-extra --policy extra


Add the reported role to an existing version 2 image's application repositories:


.. code-block:: perl

  chdef -t osimage freebsd-compute -p otherpkgdir=/install/freebsd15.1/x86_64/repositories/<digest>/repository


Set \ ``otherpkglist``\  separately to select application packages. Adding a
repository reference does not itself install packages or enable deployment
with an incomplete image definition.

After creating protected list files and adding the solver to the policy:


.. code-block:: perl

  chdef -t osimage freebsd-compute pkglist=/etc/xcat/freebsd/base.pkglist otherpkglist=/etc/xcat/freebsd/apps.pkglist
  freebsdrepo plan freebsd-compute



************
RETURN VALUE
************


0: The command completed successfully.

Nonzero: The arguments, policy, source, native validation or publication failed.


********
SEE ALSO
********


copycds(8)|copycds.8, chdef(1)|chdef.1, site(5)|site.5
