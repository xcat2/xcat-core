Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`rhels-os-support-label` on to your target Management Node

.. include:: ../common_sections.rst
   :start-after: BEGIN_install_os_mgmt_node
   :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the yum package manager on RHEL Linux distributions to install and resolve dependency packages provided by the base operating system.  Follow this section to create the repository for the base operating system on the Management Node

#. Copy the DVD iso file to ``/tmp`` on the Management Node: ::

     # This example will use RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso
   
#. Mount the iso to ``/mnt/iso/rhels7.1`` on the Management Node.  ::

     mkdir -p /mnt/iso/rhels7.1
     mount -o loop /tmp/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /mnt/iso/rhels7.1

#. Create a yum repository file ``/etc/yum.repos.d/rhels71-dvd.repo`` that points to the locally mounted iso image from the above step.  The file contents should appear as the following: ::

     [rhel-7.1-dvd-server]
     name=RHEL 7 SERVER packages
     baseurl=file:///mnt/iso/rhels7.1/Server
     enabled=1
     gpgcheck=1


Set up Network
--------------

.. include:: ../common_sections.rst
  :start-after: BEGIN_setup_mgmt_node_network
  :end-before: END_setup_mgmt_node_network 

