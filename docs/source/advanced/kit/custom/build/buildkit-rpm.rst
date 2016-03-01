Requirements
============

The ``xCAT-buildkit`` rpm is required to create xCAT Software Kits.  This rpm should be installed along with the rest of xCAT.

If the xCAT management node is not intended to be used to build the Software Kit, refer to the :doc:`Install Guide </guides/install-guides/index>` to configure the xCAT repository on the target node and install ``xCAT-buildkit`` using one of the following commands:

* **[RHEL]** ::

   yum clean metadata
   yum install xCAT-buildkit

* **[SLES]** ::

   zypper clean
   zypper install xCAT-buildkit

* **[UBUNTU]** ::

   apt-get clean
   apt-get install xcat-buildkit

