Releases
========

This section describes how xCAT versions are numbered, how a fix reaches a maintained release,
and how a maintainer publishes a release.

.. toctree::
   :maxdepth: 2

   pull_requests.rst
   checklist.rst

Branches and Versions
---------------------

xCAT has one development branch and one maintenance branch for each minor release.

* ``master`` is the development line of the next minor release.
* ``X.Y``, for example ``2.19``, is the maintenance branch of the X.Y series. It receives only
  fixes that are backported from ``master``. The patch releases X.Y.1, X.Y.2 and later are tagged
  on it.

The ``Version`` file at the top of the tree is the only place that holds the version.
``buildrpms.pl`` and ``builddebs.pl`` read it, and each build adds the release string
``snapYYYYMMDDHHMM`` from the commit time. A release is the build of the tagged commit. There is no
separate release build.

.. list-table::
   :header-rows: 1

   * - Branch
     - ``Version`` holds
     - Example after 2.19.0 is released
   * - ``master``
     - the next minor release
     - ``2.20.0``
   * - ``X.Y``
     - the next release of the series
     - ``2.19.1``

The ``release`` value in ``docs/source/conf.py`` must be the same as ``Version`` on the same
branch, because Read the Docs shows it in the title of each page. Change the two files in the same
pull request.

A released version number is never used again. The :doc:`checklist` changes ``Version`` so that
no build after a release carries the number of that release.

Tags
----

Each release has a signed annotated tag named ``X.Y.Z``, for example ``2.19.1``. The tag points at
the commit that the published packages were built from. Release candidates do not get tags,
because Read the Docs builds a documentation version for each new tag.

Package Channels
----------------

The download server has three channels under https://xcat.org/files/xcat/repos/yum/ and
https://xcat.org/files/xcat/repos/apt/:

* ``devel``: development snapshots from ``master``, in ``devel/core-snap`` and ``devel/xcat-dep``.
* ``X.Y``: the most recent release of the X.Y series. A patch release replaces the contents of
  its series directory.
* ``latest``: the most recent release series. ``go-xcat`` installs from ``latest`` by default, so
  when ``latest`` changes, new installations get the new release.

The offline bundles are in https://xcat.org/files/xcat/xcat-core/ and
https://xcat.org/files/xcat/xcat-dep/.
