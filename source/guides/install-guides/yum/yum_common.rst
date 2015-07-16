.. BEGIN_configure_base_os_repository

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


.. END_configure_base_os_repository




.. BEGIN_disable_firewall
.. DEPRECATED: Firewall instructions is not applicable after xCAT 2.8

The management node provides many services to the cluster nodes.  Running a firewall on the management node can interfere with these services.  
If your cluster is running on a secure network, the easiest thing to do is disable the firewall on the management node:: 

   service iptables stop
   service ip6tables stop

.. END_disable_firewall
