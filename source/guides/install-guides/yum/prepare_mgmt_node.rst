Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`rhels-os-support-label` on to your target management node

  .. include:: ../common/install_guide.rst
     :start-after: BEGIN_install_os_mgmt_node
     :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the yum package manager on RHEL Linux distributions to install and resolve dependency packages provded by the base operating system.  Follow this section to create the repository for the base operating system on the management node

#. Copy the dvd .iso file onto the management node: ::

     mkdir -p /tmp/iso
     scp <user>@<server>:/images/iso/rhels7.1/ppc64le/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /tmp/iso
   
#. Mount the dvd iso to a directory on the management node.  ::

     #
     # Assuming we are mounting at /mnt/iso/rhels7.1
     #
     mkdir -p /mnt/iso/rhels7.1
     mount -o loop /tmp/iso/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /mnt/iso/rhels7.1

#. Create the local repository configuration file pointing to mounted iso image. ::

     cat /etc/yum/yum.repos.d/rhels71-base.repo
     [rhel-7-server]
     name=RHEL 7 SERVER packages
     baseurl=file:///mnt/iso/rhels71/Server
     enabled=1
     gpgcheck=1


Set up Network
--------------

The management node IP address should be set to a **static** ip address.  

Modify the ifcfg-<nic> file under ``/etc/sysconfig/network-scripts`` and configure a static IP address.

