Configure xCAT Software Repository
==================================

xCAT software and repo files can be obtained from: `<http://xcat.org/download.html>`_

Internet Repository
-------------------

Install ``xCAT-release`` to configure the core, distribution-specific
dependency, and common dependency repositories and their signing key::

    dnf install https://xcat.org/files/xcat/repos/yum/latest/xcat-core/xCAT-release-latest.noarch.rpm

The distribution-specific repository follows the operating-system release and
architecture reported by DNF.  The common repository carries packages that do
not depend on the management-node distribution, including OpenEmbedded Genesis
images.  The installed repository files are marked as configuration files, so
package upgrades preserve local changes.

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

.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-dep_COMMON_MIRROR
   :end-before: END_configure_xcat_local_repo_xcat-dep_COMMON_MIRROR

.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-dep_DNF
   :end-before: END_configure_xcat_local_repo_xcat-dep_DNF
