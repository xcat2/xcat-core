Configure xCAT Software Repository
==================================

xCAT software and repo files can be obtained from: `<http://xcat.org/download.html>`_

Internet Repository
-------------------

**[xcat-core]**

From the xCAT download page, find the build you want to install and add to ``/etc/apt/sources.list``. 

To configure the xCAT development build, add the following line to ``/etc/apt/sources.list``: ::

  [For x86_64 servers]
  deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/devel/core-snap trusty main
  [For ppc64el servers]
  deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/devel/core-snap trusty main


**[xcat-dep]**

To configure the xCAT deps online repository, add the following line to ``/etc/apt/sources.list``: ::

  [For x86_64 servers]
  deb [arch=amd64] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main
  [For ppc64el servers]
  deb [arch=ppc64el] http://xcat.org/files/xcat/repos/apt/xcat-dep trusty main


If using internet repositories, continue to the next step to install xCAT.

Local Repository
----------------

.. xcat-core
.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-core_DEBIAN
   :end-before: END_configure_xcat_local_repo_xcat-core_DEBIAN

.. xcat-dep
.. include:: ../common_sections.rst
   :start-after: BEGIN_configure_xcat_local_repo_xcat-dep_DEBIAN
   :end-before: END_configure_xcat_local_repo_xcat-dep_DEBIAN
