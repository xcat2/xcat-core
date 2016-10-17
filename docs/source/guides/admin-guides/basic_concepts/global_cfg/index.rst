Global Configuration
====================

All the xCAT global configurations are stored in site table, xCAT Admin can adjust the configuration by modifying the site attribute with ``tabedit``.    

This section only presents some key global configurations, for the complete reference on the xCAT global configurations, refer to the ``tabdump -d site``.


Database Attributes
-------------------

* excludenodes: 
  A set of comma separated nodes and/or groups that would automatically be subtracted from any noderange, it can be used for excluding some failed nodes from any xCAT command. See :doc:`noderange </guides/admin-guides/references/man3/noderange.3>` for details on supported formats.

* nodestatus:  
  If set to ``n``, the ``nodelist.status`` column will not be updated during the node deployment, node discovery and power operations. The default is to update.


DHCP Attributes
---------------

* dhcpinterfaces:  
  The network interfaces DHCP should listen on.  If it is the same for all nodes, use a simple comma-separated list of NICs.  To specify different NICs for different nodes ::

     xcatmn|eth1,eth2;service|bond0.

  In this example xcatmn is the name of the xCAT MN, and DHCP there should listen on eth1 and eth2.  On all of the nodes in group ``service`` DHCP should listen on the bond0 nic.

* dhcplease:  
  The lease time for the dhcp client. The default value is 43200.


* managedaddressmode: 
  The mode of networking configuration during node provision. 
  If set to ``static``, the network configuration will be configured in static mode based on the node and network definition on MN.
  If set to ``dhcp``, the network will be configured with dhcp protocol.
  The default is ``dhcp``.


DNS Attributes
--------------

* domain:  
  The DNS domain name used for the cluster.

* forwarders:  
  The DNS servers at your site that can provide names outside of the cluster. The ``makedns`` command will configure the DNS on the management node to forward requests it does not know to these servers.
  **Note** that the DNS servers on the service nodes will ignore this value and always be configured to forward requests to the management node.

* master:  
  The hostname of the xCAT management node, as known by the nodes.

* nameservers:  
  A comma delimited list of DNS servers that each node in the cluster should use. This value will end up in the nameserver settings of the ``/etc/resolv.conf`` on each node. It is common (but not required) to set this attribute value to the IP addr of the xCAT management node, if you have set up the DNS on the management node by running ``makedns``. In a hierarchical cluster, you can also set this attribute to ``<xcatmaster>`` to mean the DNS server for each node should be the node that is managing it (either its service node or the management node).


* dnsinterfaces:  
  The network interfaces DNS server should listen on.  If it is the same for all nodes, use a simple comma-separated list of NICs.  To specify different NICs for different nodes ::

     xcatmn|eth1,eth2;service|bond0.

  In this example xcatmn is the name of the xCAT MN, and DNS there should listen on eth1 and eth2.  On all of the nodes in group ``service`` DNS should listen on the bond0 nic.

  **NOTE**: if using this attribute to block certain interfaces, make sure the ip that maps to your hostname of xCAT MN is not blocked since xCAT needs to use this ip to communicate with the local DNS server on MN.


Install/Deployment Attributes
-----------------------------

* installdir:  
  The local directory name used to hold the node deployment packages.

* runbootscripts:  
  If set to ``yes`` the scripts listed in the postbootscripts attribute in the osimage and postscripts tables will be run during each reboot of stateful (diskful) nodes. This attribute has no effect on stateless nodes. Run the following command after you change the value of this attribute :: 

   updatenode <nodes> -P setuppostbootscripts

* precreatemypostscripts: 
  (``yes/1`` or ``no/0``). Default is ``no``. If yes, it will instruct xCAT at ``nodeset`` and ``updatenode`` time to query the db once for all of the nodes passed into the cmd and create the mypostscript file for each node, and put them in a directory of tftpdir(such as: /tftpboot). If no, it will not generate the mypostscript file in the ``tftpdir``.

* xcatdebugmode:  
  the xCAT debug level. xCAT provides a batch of techniques to help user debug problems while using xCAT, especially on OS provision, such as collecting logs of the whole installation process and accessing the installing system via ssh, etc. These techniques will be enabled according to different xCAT debug levels specified by 'xcatdebugmode', currently supported values: ::

    '0':  disable debug mode
    '1':  enable basic debug mode
    '2':  enable expert debug mode

  For the details on 'basic debug mode' and 'expert debug mode', refer to xCAT documentation.


Remoteshell Attributes
----------------------

* sshbetweennodes: 
  Comma separated list of groups of compute nodes to enable passwordless root ssh during install, or ``xdsh -K``. Default is ``ALLGROUPS``. Set to ``NOGROUPS`` if you do not wish to enable it for any group of compute nodes. If using the ``zone`` table, this attribute in not used.


Services Attributes
-------------------

* consoleondemand:  
  When set to ``yes``, conserver connects and creates the console output only when the user opens the console. Default is ``no`` on Linux, ``yes`` on AIX.

* timezone:  
  The timezone for all the nodes in the cluster(e.g. ``America/New_York``).

* tftpdir:  
  tftp directory path. Default is /tftpboot.

* tftpflags:  
  The flags used to start tftpd. Default is ``-v -l -s /tftpboot -m /etc/tftpmapfile4xcat.conf`` if ``tftplfags`` is not set.


Virtualization Attributes
--------------------------

* persistkvmguests:  
  Keep the kvm definition on the kvm hypervisor when you power off the kvm guest node. This is useful for you to manually change the kvm xml definition file in ``virsh`` for debugging. Set anything means ``enable``.


xCAT Daemon attributes
----------------------

* xcatdport:  
  The port used by xcatd daemon for client/server communication.

* xcatiport:  
  The port used by xcatd to receive installation status updates from nodes.

* xcatlport:  
  The port used by xcatd command log writer process to collect command output.

* xcatsslversion:  
  The ssl version by xcatd. Default is ``SSLv3``.

* xcatsslciphers:  
  The ssl cipher by xcatd. Default is ``3DES``.



