Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`sles-os-support-label` on to your target management node

  .. include:: ../common/install_guide.rst
     :start-after: BEGIN_install_os_mgmt_node
     :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the zypper package manager on SLES Linux distributions to install and resolve dependency packages provded by the base operating system.  Follow this section to create the repository for the base operating system on the management node

#. Copy the dvd .iso file onto the management node: ::

     mkdir -p /tmp/iso
     scp <user>@<server>:/images/iso/sles12/ppc64le/SLE-12-Server-DVD-ppc64le-GM-DVD1.iso /tmp/iso
   
#. Mount the dvd iso to a directory on the management node.  ::

     #
     # Assuming we are mounting at /mnt/iso/sles12
     #
     mkdir -p /mnt/iso/sles12
     mount -o loop /tmp/iso/SLE-12-Server-DVD-ppc64le-GM-DVD1.iso /mnt/iso/sles12

#. Create the local repository configuration file pointing to mounted iso image. ::

     cat /etc/zypp/repos.d/sles12le-base.repo
     [sles-12-le-server]
     name=SLES 12 ppc64le Server Packages
     baseurl=file:///mnt/iso/sles12/suse
     enabled=1
     gpgcheck=1


Set up Network
--------------

The management node IP address should be set to a **static** ip address.  

Modify the ifcfg-<nic> file under ``/etc/sysconfig/network-scripts`` and configure a static IP address.

