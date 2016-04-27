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


Configure the Management Node
-----------------------------

By setting properties on the Management Node before installing the xCAT software will allow xCAT to automatically configure key attributes in the xCAT ``site`` table during the install.

#. Ensure a hostname is configured on the management node by issuing the ``hostname`` command.  [*It's recommended to use a fully qualified domain name (FQDN) when setting the hostname*]

   #. To set the hostname of *xcatmn.cluster.com*: ::

       hostname xcatmn.cluster.com 

   #. Add the hostname to the ``/etc/hostname`` in order to persist the hostname on reboot.

   
   #. Reboot the server and verify the hostname by running the following commands: 

        * ``hostname``
        * ``hostname -d`` - should display the domain

#. Reduce the risk of the Management Node IP address being lost by setting the IP to **STATIC** in the ``/etc/sysconfig/network/ifcfg-<dev>`` configuration files.

#. Configure any domain search strings and nameservers to the ``/etc/resolv.conf`` file.
