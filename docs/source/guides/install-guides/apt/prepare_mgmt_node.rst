Prepare the Management Node
===========================

These steps prepare the Management Node or xCAT Installation

Install an OS on the Management Node
------------------------------------

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


Configure the Management Node
-----------------------------

By setting properties on the Management Node before installing the xCAT software will allow xCAT to automatically configure key attributes in the xCAT ``site`` table during the install.

#. Ensure a hostname is configured on the management node by issuing the ``hostname`` command.  [*It's recommended to use a fully qualified domain name (FQDN) when setting the hostname*]

   #. To set the hostname of *xcatmn.cluster.com*: ::

       hostname xcatmn.cluster.com 

   #. Add the hostname to the ``/etc/hostname`` and ``/etc/hosts`` to persist the hostname on reboot. 
   
   #. Reboot or run ``service hostname restart`` to allow the hostname to take effect and verify the hostname command returns correctly:

        * ``hostname``
        * ``hostname -d`` - should display the domain

#. Reduce the risk of the Management Node IP address being lost by setting the interface IP to **STATIC** in the ``/etc/network/interfaces`` configuration file.

#. Configure any domain search strings and nameservers using the ``resolvconf`` command. 
