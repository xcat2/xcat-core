Configure xCAT Software Repository
==================================

xCAT software and repo files can be obtained from: `<http://xcat.org/download.html>`_

Internet Repository
-------------------

Install ``xcat-release`` to configure both the ``xcat-core`` and ``xcat-dep``
repositories and their signing key::

    dnf install https://xcat.org/files/xcat/repos/yum/latest/xcat-core/xcat-release-latest.noarch.rpm

The dependency repository is selected automatically from the operating-system
release and architecture reported by DNF.  The installed repository files are
marked as configuration files, so package upgrades preserve local changes.

Continue to the next section to install xCAT.

Local Repository
----------------

.. xcat-core
.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-core_RPM
   :end-before: END_configure_xcat_local_repo_xcat-core_RPM

.. xcat-dep
.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-dep_RPM
   :end-before: END_configure_xcat_local_repo_xcat-dep_RPM
