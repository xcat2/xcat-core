.. BEGIN_configure_base_os_repository

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


.. END_configure_base_os_repository




.. BEGIN_disable_firewall
.. DEPRECATED: Firewall instructions is not applicable after xCAT 2.8

The management node provides many services to the cluster nodes.  Running a firewall on the management node can interfere with these services.  
If your cluster is running on a secure network, the easiest thing to do is disable the firewall on the management node:: 

   service iptables stop
   service ip6tables stop

.. END_disable_firewall

