Prepare the Management Node
===========================

These steps prepare the Management Node for xCAT Installation

Install an OS on the Management Node
------------------------------------

.. include:: ../common_sections.rst
   :start-after: BEGIN_install_os_mgmt_node
   :end-before: END_install_os_mgmt_node

Configure the Base OS Repository
--------------------------------

xCAT uses the yum package manager on RHEL Linux distributions to install and resolve dependency packages provided by the base operating system.  Follow this section to create the repository for the base operating system on the Management Node

#. Copy the DVD iso file to ``/tmp`` on the Management Node.  
   This example will use file ``RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso``
   
#. Mount the iso to ``/mnt/iso/rhels7.1`` on the Management Node.  ::

     mkdir -p /mnt/iso/rhels7.1
     mount -o loop /tmp/RHEL-LE-7.1-20150219.1-Server-ppc64le-dvd1.iso /mnt/iso/rhels7.1

#. Create a yum repository file ``/etc/yum.repos.d/rhels71-dvd.repo`` that points to the locally mounted iso image from the above step.  The file contents should appear as the following: ::

     [rhel-7.1-dvd-server]
     name=RHEL 7 SERVER packages
     baseurl=file:///mnt/iso/rhels7.1/Server
     enabled=1
     gpgcheck=1


Configure the Management Node
-----------------------------

By setting properties on the Management Node before installing the xCAT software will allow xCAT to automatically configure key attributes in the xCAT ``site`` table during the install.

#. Ensure a hostname is configured on the management node by issuing the ``hostname`` command.  [*It's recommended to use a fully qualified domain name (FQDN) when setting the hostname*]

   #. To set the hostname of *xcatmn.cluster.com*: ::

       hostname xcatmn.cluster.com 

   #. Add the hostname to the ``/etc/sysconfig/network`` in order to persist the hostname on reboot.

   
   #. Reboot the server and verify the hostname by running the following commands: 

        * ``hostname``
        * ``hostname -d`` - should display the domain

#. Reduce the risk of the Management Node IP address being lost by setting the IP to **STATIC** in the ``/etc/sysconfig/network-scripts/ifcfg-<dev>`` configuration files.

#. Configure any domain search strings and nameservers to the ``/etc/resolv.conf`` file.

