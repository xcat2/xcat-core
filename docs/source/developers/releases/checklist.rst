Release Checklist
=================

A maintainer with publish access to the download server does these steps. The build hosts, the
signing key and the publish procedure are in the private repository of the maintainers. This page
does not repeat them.

The steps use these names:

* ``X.Y.Z``: the new release, for example ``2.19.1``.
* ``P``: the tag of the previous release in the same series, for example ``2.19.0``. For X.Y.0,
  use the tag of the previous minor release.
* ``<commit>``: the full id of the release commit.
* ``<page>``: the name of the release notes page on the wiki.

Plan
----

#. Open the milestone of the release: ``X.Y.Z`` for a patch release, ``X.Y`` for X.Y.0. Make sure
   that each closed pull request in it is merged on the ``X.Y`` branch. For a backported fix, the
   ``[Backport X.Y]`` pull request must also be merged.

#. Move each open item to the next milestone, or finish it before the release candidates start.

Start a Minor Release
---------------------

Do these steps once for X.Y.0, when the release candidates start. You must have admin rights on
``xcat2/xcat-core``.

#. Create the ``X.Y`` branch from the head of ``master``: ::

    $ gh api -X POST repos/xcat2/xcat-core/git/refs -f ref=refs/heads/X.Y -f sha=<commit>

#. Add ``refs/heads/X.Y`` to the target branches of the ``release-branches`` ruleset, in
   Settings, Rules, Rulesets.

#. Create the backport label: ::

    $ gh label create "backport X.Y" -R xcat2/xcat-core --color 0e8a16 \
        --description "Backport this PR to the X.Y maintenance branch"

#. Create the milestone ``X.Y.1`` and the milestone of the next minor release, if they do not
   exist.

#. Open a pull request against ``master`` that sets ``Version`` and the ``release`` value in
   ``docs/source/conf.py`` to the next minor release, for example ``2.21.0`` after the ``2.20``
   branch is created.

After these steps, a fix for X.Y.0 goes to ``master`` with the label ``backport X.Y`` and the
milestone ``X.Y``.

When a series gets no more releases, delete its backport label.

Prepare the Release Branch
--------------------------

#. Add a row to ``docs/source/overview/_files/X.Y.x.csv``. For X.Y.0, create the file and add a
   section for it at the top of ``docs/source/overview/xcat2_release.rst``. A row has this form: ::

    2.18.0,2026-06-22,"RHEL 10,AlmaLinux 10",`2.18.0 Release Notes <https://github.com/xcat2/xcat-core/wiki/XCAT_2.18_Release_Notes>`_

   Open the change against ``master`` with the label ``backport X.Y``, so that the row is on both
   branches before the tag.

#. Make sure that ``Version`` and the ``release`` value in ``docs/source/conf.py`` on the ``X.Y``
   branch are both ``X.Y.Z``.

Release Candidates
------------------

A release candidate is a build of the head of the ``X.Y`` branch. Do not create a branch or a tag
for a candidate, such as ``release/X.Y-rc1`` or ``X.Y.Z-rc1``.

#. Build a candidate from the head of the ``X.Y`` branch, and sign the packages and the
   repository metadata. Build xcat-dep too if its packages changed after the previous release.

#. Publish the candidate to a staging location only. Do not publish a candidate to ``X.Y`` or to
   ``latest``.

#. Test the candidate on each operating system and architecture that the release notes will name.
   Install a management node, and provision stateful and stateless compute nodes. Record what you
   tested, because the release notes report it.

#. If a test fails, fix the problem on ``master``, backport the fix, and build the next candidate
   from the new head of ``X.Y``.

The ``COMMIT_ID_LONG`` line in the ``buildinfo.txt`` file of a candidate identifies it.

Build and Publish
-----------------

The release is the last candidate that passed the tests.

#. Record the full id of the release commit. This is the ``COMMIT_ID_LONG`` of that candidate.

#. Publish the packages of that candidate to ``repos/yum/X.Y/`` and ``repos/apt/X.Y/``. Do not
   build them again. A new build from the same commit can give different packages, for example a
   Genesis image with a newer kernel. If you must build a package again, test the new build as a
   candidate before you publish it.

#. Upload the offline bundles: ::

    xcat-core/X.Y.x_Linux/xcat-core-X.Y.Z-linux.tar.bz2
    xcat-core/X.Y.x_Ubuntu/xcat-core-X.Y.Z-ubuntu.tar.bz2
    xcat-dep/2.x_Linux/xcat-dep-X.Y.Z-linux.tar.bz2
    xcat-dep/2.x_Ubuntu/xcat-dep-X.Y.Z-ubuntu.tar.bz2

#. Make sure that each ``.repo`` file under ``repos/yum/X.Y/`` points at ``repos/yum/X.Y/``, not at
   ``devel`` or ``latest``. ``latest`` is a link into the newest series, so a series path is right
   through both. A file that names ``latest`` gives the next series to users of this one as soon as
   that series ships.

#. If X.Y is the newest series, point ``latest`` at ``X.Y`` for yum and for apt.

#. Make sure that ``devel`` does not serve a build that is older than the release.

Verify the Published Packages
-----------------------------

#. Check that ``buildinfo.txt`` shows ``VERSION=X.Y.Z`` and ``COMMIT_ID_LONG=<commit>``. If you
   changed ``latest``, check it too: ::

    $ curl -fsS https://xcat.org/files/xcat/repos/yum/X.Y/xcat-core/buildinfo.txt
    $ curl -fsS https://xcat.org/files/xcat/repos/yum/latest/xcat-core/buildinfo.txt

#. Check the signatures of the repository metadata against the key that ``xCAT-release`` ships.
   Use a keyring that holds only ``xCAT-release/RPM-GPG-KEY-xCAT``, so that no other key can pass
   the check: ::

    $ gpg --dearmor <xCAT-release/RPM-GPG-KEY-xCAT >xcat-release.gpg
    $ curl -fsSO https://xcat.org/files/xcat/repos/yum/X.Y/xcat-core/repodata/repomd.xml
    $ curl -fsSO https://xcat.org/files/xcat/repos/yum/X.Y/xcat-core/repodata/repomd.xml.asc
    $ gpgv --keyring ./xcat-release.gpg repomd.xml.asc repomd.xml

   Do the same for ``xcat-dep/common`` and for each ``xcat-dep/rh<N>/<arch>`` directory. For apt,
   check ``dists/<codename>/InRelease`` of xcat-core and xcat-dep for each codename: ::

    $ curl -fsSO https://xcat.org/files/xcat/repos/apt/X.Y/xcat-core/dists/<codename>/InRelease
    $ gpgv --keyring ./xcat-release.gpg InRelease

#. Check that each offline bundle URL answers with HTTP 200: ::

    $ curl -fsSI https://xcat.org/files/xcat/xcat-core/X.Y.x_Linux/xcat-core-X.Y.Z-linux.tar.bz2

#. Install xCAT with signature checks on a new EL host and on a new Ubuntu host. ``go-xcat``
   turns these checks off with ``dnf --nogpgcheck`` and ``apt-get --allow-unauthenticated``, so a
   ``go-xcat`` installation does not prove the signatures.

   On EL, use the three published ``.repo`` files, which set ``gpgcheck=1``. Enable the other
   repositories that the installation guide requires first. Use the files as published: each one
   must point at ``repos/yum/X.Y/``. Install the Genesis image for the host architecture by name,
   because ``xCAT`` only recommends it. ::

    $ curl -fsSo /etc/yum.repos.d/xcat-core.repo \
        https://xcat.org/files/xcat/repos/yum/X.Y/xcat-core/xcat-core.repo
    $ curl -fsSo /etc/yum.repos.d/xcat-dep.repo \
        https://xcat.org/files/xcat/repos/yum/X.Y/xcat-dep/rh<N>/<arch>/xcat-dep.repo
    $ curl -fsSo /etc/yum.repos.d/xcat-dep-common.repo \
        https://xcat.org/files/xcat/repos/yum/X.Y/xcat-dep/common/xcat-dep-common.repo
    $ dnf install -y xCAT xCAT-genesis-openembedded-<arch>
    $ lsxcatd -v

   On Ubuntu, add the repositories with their signing keys. ``apt-get update`` must not report a
   signature error. ::

    $ url=https://xcat.org/files/xcat/repos/apt/X.Y
    $ codename=$(. /etc/os-release && echo "$VERSION_CODENAME")
    $ curl -fsSL $url/xcat-core/apt.key | gpg --dearmor -o /usr/share/keyrings/xcat-core.gpg
    $ curl -fsSL $url/xcat-dep/apt.key | gpg --dearmor -o /usr/share/keyrings/xcat-dep.gpg
    $ echo "deb [signed-by=/usr/share/keyrings/xcat-core.gpg] $url/xcat-core $codename main" \
        >/etc/apt/sources.list.d/xcat.list
    $ echo "deb [signed-by=/usr/share/keyrings/xcat-dep.gpg] $url/xcat-dep $codename main" \
        >>/etc/apt/sources.list.d/xcat.list
    $ apt-get update
    $ apt-get install -y xcat
    $ lsxcatd -v

#. Install xCAT with ``go-xcat`` on another new EL host and on a new Ubuntu host, and check the
   version: ::

    $ ./go-xcat -x X.Y -y install
    $ lsxcatd -v

   If you changed ``latest``, also install once without ``-x X.Y``.

Release Notes
-------------

The release notes are a page on the `xcat-core wiki <https://github.com/xcat2/xcat-core/wiki>`_.

#. Name the page ``XCAT_X.Y_Release_Notes`` for X.Y.0, and ``XCAT_X.Y.Z_Release_Notes`` for a
   patch release. Do not rename the page later, because other pages and https://xcat.org link to
   it.

#. Start from the notes of the previous release of the same kind, and keep the order of the
   sections: ::

    # xCAT X.Y.Z Release Notes (Month D, YYYY)
    ## Operating System Support
    ## Highlighted Changes
    ## Download xCAT
    ### Offline tarball bundles
    ## Validation
    ## Key Issues Resolved
    ## Documentation

#. Run each command in "Download xCAT" on a new host, and open each link.

#. Report only the tests that were done, with the operating system, the architecture and the
   node types.

#. For a patch release, add a line at the top of the X.Y notes page that links to the new page.

Tag
---

Create a signed annotated tag on the release commit, and push only the tag: ::

    $ git fetch upstream
    $ git tag -s X.Y.Z -m "xCAT X.Y.Z" <commit>
    $ git tag -v X.Y.Z
    $ git push upstream refs/tags/X.Y.Z

Do not create the tag from the GitHub release page. That page creates a lightweight tag with no
signature.

GitHub Release
--------------

Write the release text to a file, for example ``notes.md``: ::

    The release notes for X.Y.Z are available at https://github.com/xcat2/xcat-core/wiki/<page>

    Full changelog: https://github.com/xcat2/xcat-core/compare/P...X.Y.Z

Then create the release from the tag: ::

    $ gh release create X.Y.Z -R xcat2/xcat-core --verify-tag --title X.Y.Z --notes-file notes.md

For a patch release of a series that is not the newest, add ``--latest=false``.

Read the Docs
-------------

Read the Docs builds a documentation version for each new tag, and ``stable`` follows the highest
version tag.

#. Open https://xcat-docs.readthedocs.io/en/X.Y.Z/, and check that the build passed and that the
   title shows X.Y.Z.

#. If X.Y.Z is the highest release, check that https://xcat-docs.readthedocs.io/en/stable/ shows
   X.Y.Z. For a patch release of an older series, check that ``stable`` did not change.

Wiki Index Pages
----------------

#. On the ``test_sidebar`` page, which holds the News list, add a line at the top: ::

    * Mon DD, YYYY: [xCAT X.Y.Z](<page>) released.

#. For X.Y.0, add a row for X.Y to the "General Release Information and Planning" table on the
   ``Home`` page, and move the ``(stable)`` marker to it.

Website
-------

The ``xcat2/xcat2.github.io`` repository holds the pages of https://xcat.org. The default
downloads on these pages must stay on the same series as ``latest``.

If X.Y is the newest series:

#. In ``index.html``, change the release line and the release notes link.

#. In ``download.html``, change the version and the offline bundle links.

#. In ``footer.html``, change the release news link.

For a patch release of an older series, do not change the default version on these pages. Add the
older release to ``download.html`` as a separate entry.

Commit the change in the repository, copy the changed files to the web server, and open each
changed link on https://xcat.org.

Announcement
------------

Send an email to xcat-user@lists.sourceforge.net with the subject
``Announcement: xCAT X.Y.Z released``. Use the announcement of the previous release as the model: ::

    Dear xCAT community,

    We are pleased to announce the release of xCAT X.Y.Z.
    <one or two sentences about the release>

    Highlights:
    * <area>
      - <change>

    Full release notes: https://github.com/xcat2/xcat-core/wiki/<page>
    Downloads: https://github.com/xcat2/xcat-core/releases/tag/X.Y.Z

    <thanks to contributors and reporters>

    We welcome your feedback, bug reports, and contributions:
    https://github.com/xcat2/xcat-core

    Best regards,
    <name>
    on behalf of the xCAT Consortium

Keep the announcement of a patch release short, and name the fixes it contains.

After the Release
-----------------

#. Close the milestone of the release. Create the milestone ``X.Y.(Z+1)`` if it does not exist,
   and move the open items to it.

#. Open a pull request against ``X.Y`` that sets ``Version`` and the ``release`` value in
   ``docs/source/conf.py`` to ``X.Y.(Z+1)``.

#. For X.Y.0, make sure that the steps in "Start a Minor Release" are complete.
