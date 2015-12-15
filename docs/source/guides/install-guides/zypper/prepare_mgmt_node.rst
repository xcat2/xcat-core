Prepare the Management Node
===========================

These steps prepare the Management Node for xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`sles-os-support-label` on to your target Management Node

.. include:: ../common_sections.rst
   :start-after: BEGIN_install_os_mgmt_node
   :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the zypper package manager on SLES Linux distributions to install and resolve dependency packages provided by the base operating system.  Follow this section to create the repository for the base operating system on the Management Node

#. Copy the DVD iso file to ``/tmp`` on the Management Node: ::

     # This example will use SLE-12-Server-DVD-ppc64le-GM-DVD1.iso
   
#. Mount the iso to ``/mnt/iso/sles12`` on the Management Node.  ::

     mkdir -p /mnt/iso/sles12
     mount -o loop /tmp/SLE-12-Server-DVD-ppc64le-GM-DVD1.iso /mnt/iso/sles12

#. Create a zypper repository file ``/etc/zypp/repos.d/sles12le-base.repo`` that points to the locally mounted iso image from the above step.  The file contents should appear as the following: ::

     [sles-12-le-server]
     name=SLES 12 ppc64le Server Packages
     baseurl=file:///mnt/iso/sles12/suse
     enabled=1
     gpgcheck=1


Set up Network
--------------

The Management Node IP address should be set to a **static** IP address.

Modify the ``ifcfg-<device>`` file in ``/etc/sysconfig/network/`` and configure a static IP address.

