Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

Install one of the supported operating systems :ref:`ubuntu-os-support-label` on to your target management node

.. include:: ../common_sections.rst
  :start-after: BEGIN_install_os_mgmt_node
  :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the apt package manager on Ubuntu Linux distributions to install and resolve dependency packages provided by the base operating system.  Follow this section to create the repository for the base operating system on the Management Node

#. Copy the DVD iso file to ``/tmp`` on the Management Node: ::

     # This example will use ubuntu-14.04.3-server-ppc64el.iso

#. Mount the iso to ``/mnt/iso/ubuntu14`` on the Management Node.  ::

     mkdir -p /mnt/iso/ubuntu14
     mount -o loop /tmp/ubuntu-14.04.3-server-ppc64el.iso /mnt/iso/ubuntu14

#. Create an apt repository file ``/etc/apt.repos.d/ubuntu14-dvd.repo`` that points to the locally mounted iso image from the above step.  The file contents should appear as the following: ::

     [ubuntu-14-dvd-server]
     name=UBUNTU 14 SERVER packages
     baseurl=file:///mnt/iso/ubuntu14/Server
     enabled=1
     gpgcheck=1


Set up Network
--------------

The Management Node IP address should be set to a **static** IP address.

Modify the ``interfaces`` file in ``/etc/network`` and configure a static IP address.	::
    
    # The primary network interface
    auto eth0
    iface eth0 inet static
        address 10.3.31.11
        netmask 255.0.0.0

