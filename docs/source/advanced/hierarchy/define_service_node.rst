Define the service nodes in the database
========================================

This document assumes that you have previously **defined** your compute nodes
in the database. It is also possible at this point that you have generic
entries in your db for the nodes you will use as service nodes as a result of
the node discovery process. We are now going to show you how to add all the
relevant database data for the service nodes (SN) such that the SN can be
installed and managed from the Management Node (MN). In addition, you will
be adding the information to the database that will tell xCAT which service
nodes (SN) will service which compute nodes (CN).

For this example, we have two service nodes: **sn1** and **sn2**. We will call
our Management Node: **mn1**. Note: service nodes are, by convention, in a
group called **service**. Some of the commands in this document will use the
group **service** to update all service nodes.

Note: a Service Node's service node is the Management Node; so a service node
must have a direct connection to the management node. The compute nodes do not 
have to be directly attached to the Management Node, only to their service 
node. This will all have to be defined in your networks table.

Add Service Nodes to the nodelist Table
---------------------------------------

Define your service nodes (if not defined already), and by convention we put
them in a **service** group. We usually have a group compute for our compute
nodes, to distinguish between the two types of nodes. (If you want to use your 
own group name for service nodes, rather than service, you need to change some 
defaults in the xCAT db that use the group name service. For example, in the 
postscripts table there is by default a group entry for service, with the 
appropriate postscripts to run when installing a service node. Also, the 
default ``kickstart/autoyast`` template, pkglist, etc that will be used have
files names based on the profile name service.) ::

  mkdef sn1,sn2 groups=service,ipmi,all

Add OS and Hardware Attributes to Service Nodes
-----------------------------------------------

When you ran copycds, it creates several osimage definitions, including some
appropriate for SNs. Display the list of osimages and choose one with
"service" in the name: ::

   lsdef -t osimage

For this example, let's assume you chose the stateful osimage definition for 
rhels 7: rhels7-x86_64-install-service . If you want to modify any of the
osimage attributes (e.g. ``kickstart/autoyast`` template, pkglist, etc),
make a copy of the osimage definition and also copy to ``/install/custom``
any files it points to that you are modifying.

Now set some of the common attributes for the SNs at the group level: ::

  chdef -t group service arch=x86_64 \
                         os=rhels7 \
                         nodetype=osi
                         profile=service \
                         netboot=xnba installnic=mac \
                         primarynic=mac \
                         provmethod=rhels7-x86_64-install-service

Add Service Nodes to the servicenode Table
------------------------------------------

An entry must be created in the servicenode table for each service node or the 
service group. This table describes all the services you would like xcat to 
setup on the service nodes. (Even if you don't want xCAT to set up any 
services - unlikely - you must define the service nodes in the servicenode 
table with at least one attribute set (you can set it to 0), otherwise it will 
not be recognized as a service node.)

When the xcatd daemon is started or restarted on the service node, it will 
make sure all of the requested services are configured and started. (To 
temporarily avoid this when restarting xcatd, use "service xcatd reload" 
instead.)

To set up the minimum recommended services on the service nodes: ::

  chdef -t group -o service setupnfs=1 \
                            setupdhcp=1 setuptftp=1 \
                            setupnameserver=1 \
                            setupconserver=1

.. TODO

See the ``setup*`` attributes in the :doc:`node manpage </guides/admin-guides/references/man7/node.7>` for the services available. (The HTTP server is also started when setupnfs is set.)

If you are using the setupntp postscript on the compute nodes, you should also
set setupntp=1. For clusters with subnetted management networks (i.e. the
network between the SN and its compute nodes is separate from the network
between the MN and the SNs) you might want to also set setupipforward=1.

.. _add_service_node_postscripts_label:

Add Service Node Postscripts
----------------------------

By default, xCAT defines the service node group to have the "servicenode"
postscript run when the SNs are installed or diskless booted. This
postscript sets up the xcatd credentials and installs the xCAT software on
the service nodes. If you have your own postscript that you want run on the
SN during deployment of the SN, put it in ``/install/postscripts`` on the MN
and add it to the service node postscripts or postbootscripts. For example: ::

  chdef -t group -p service postscripts=<mypostscript>

Notes:

  * For Red Hat type distros, the postscripts will be run before the reboot
    of a kickstart install, and the postbootscripts will be run after the
    reboot.
  * Make sure that the servicenode postscript is set to run before the
    otherpkgs postscript or you will see errors during the service node
    deployment.
  * The -p flag automatically adds the specified postscript at the end of the
    comma-separated list of postscripts (or postbootscripts).

If you are running additional software on the service nodes that need **ODBC**
to access the database (e.g. LoadLeveler or TEAL), use this command to add
the xCAT supplied postbootscript called "odbcsetup". ::

  chdef -t group -p service postbootscripts=odbcsetup

Assigning Nodes to their Service Nodes
--------------------------------------

The node attributes **servicenode** and **xcatmaster** define which SN
services this particular node. The servicenode attribute for a compute node
defines which SN the MN should send a command to (e.g. xdsh), and should be
set to the hostname or IP address of the service node that the management
node contacts it by. The xcatmaster attribute of the compute node defines
which SN the compute node should boot from, and should be set to the
hostname or IP address of the service node that the compute node contacts it
by. Unless you are using service node pools, you must set the xcatmaster
attribute for a node when using service nodes, even if it contains the same
value as the node's servicenode attribute.

Host name resolution must have been setup in advance, with ``/etc/hosts``, DNS
or dhcp to ensure that the names put in this table can be resolved on the
Management Node, Service nodes, and the compute nodes. It is easiest to have a 
node group of the compute nodes for each service node. For example, if all the 
nodes in node group compute1 are serviced by sn1 and all the nodes in node 
group compute2 are serviced by sn2:

::

  chdef -t group compute1 servicenode=sn1 xcatmaster=sn1-c
  chdef -t group compute2 servicenode=sn2 xcatmaster=sn2-c

Note: in this example, sn1 and sn2 are the node names of the service nodes 
(and therefore the hostnames associated with the NICs that the MN talks to). 
The hostnames sn1-c and sn2-c are associated with the SN NICs that communicate 
with their compute nodes.

Note: if not set, the attribute tftpserver's default value is xcatmaster,
but in some releases of xCAT it has not defaulted correctly, so it is safer
to set the tftpserver to the value of xcatmaster.

These attributes will allow you to specify which service node should run the 
conserver (console) and monserver (monitoring) daemon for the nodes in the 
group specified in the command. In this example, we are having each node's 
primary SN also act as its conserver and monserver (the most typical setup).
::

  chdef -t group compute1 conserver=sn1 monserver=sn1,sn1-c
  chdef -t group compute2 conserver=sn2 monserver=sn2,sn2-c

Service Node Pools
^^^^^^^^^^^^^^^^^^

Service Node Pools are multiple service nodes that service the same set of 
compute nodes. Having multiple service nodes allows backup service node(s) for 
a compute node when the primary service node is unavailable, or can be used 
for work-load balancing on the service nodes. But note that the selection of 
which SN will service which compute node is made at compute node boot time. 
After that, the selection of the SN for this compute node is fixed until the 
compute node is rebooted or the compute node is explicitly moved to another SN 
using the `snmove <http://localhost/fake_todo>`_  command.

To use Service Node pools, you need to architect your network such that all of 
the compute nodes and service nodes in a partcular pool are on the same flat 
network. If you don't want the management node to respond to manage some of
the compute nodes, it shouldn't be on that same flat network. The 
site, dhcpinterfaces attribute should be set such that the SNs' DHCP daemon
only listens on the NIC that faces the compute nodes, not the NIC that faces 
the MN. This avoids some timing issues when the SNs are being deployed (so 
that they don't respond to each other before they are completely ready). You 
also need to make sure the `networks <http://localhost/fake_todo>`_ table
accurately reflects the physical network structure.

To define a list of service nodes that support a set of compute nodes, set the 
servicenode attribute to a comma-delimited list of the service nodes. When 
running an xCAT command like xdsh or updatenode for compute nodes, the list 
will be processed left to right, picking the first service node on the list to 
run the command. If that service node is not available, then the next service 
node on the list will be chosen until the command is successful. Errors will 
be logged. If no service node on the list can process the command, then the 
error will be returned. You can provide some load-balancing by assigning your 
service nodes as we do below.

When using service node pools, the intent is to have the service node that 
responds first to the compute node's DHCP request during boot also be the 
xcatmaster, the tftpserver, and the NFS/http server for that node. Therefore, 
the xcatmaster and nfsserver attributes for nodes should not be set. When 
nodeset is run for the compute nodes, the service node interface on the 
network to the compute nodes should be defined and active, so that nodeset 
will default those attribute values to the "node ip facing" interface on that 
service node.

For example: ::

  chdef -t node compute1 servicenode=sn1,sn2 xcatmaster="" nfsserver=""
  chdef -t node compute2 servicenode=sn2,sn1 xcatmaster="" nfsserver=""

You need to set the sharedtftp site attribute to 0 so that the SNs will not 
automatically mount the ``/tftpboot`` directory from the management node:
::

  chdef -t site clustersite sharedtftp=0

For stateful (diskful) installs, you will need to use a local ``/install`` directory on each service node. The ``/install/autoinst/node`` files generated by nodeset will contain values specific to that service node for correctly installing the nodes. ::

  chdef -t site clustersite installloc=""

With this setting, you will need to remember to rsync your ``/install``
directory from the xCAT management node to the service nodes anytime you
change your ``/install/postscripts``, custom osimage files, os repositories,
or other directories. It is best to exclude the ``/install/autoinst`` directory
from this rsync.

::

  rsync -auv --exclude 'autoinst' /install sn1:/

Note: If your service nodes are stateless and site.sharedtftp=0, if you reboot 
any service node when using servicenode pools, any data written to the local 
``/tftpboot`` directory of that SN is lost. You will need to run nodeset for
all of the compute nodes serviced by that SN again.

For additional information about service node pool related settings in the
networks table, see ref: networks table, see :ref:`setup_networks_table_label`.

Conserver and Monserver and Pools
"""""""""""""""""""""""""""""""""

The support of conserver and monserver with Service Node Pools is still not 
supported. You must explicitly assign these functions to a service node using 
the nodehm.conserver and noderes.monserver attribute as above.

Setup Site Table
----------------

If you are not using the NFS-based statelite method of booting your compute 
nodes, set the installloc attribute to ``/install``. This instructs the
service node to mount ``/install`` from the management node. (If you don't do
this, you have to manually sync ``/install`` between the management node and
the service nodes.) ::

  chdef -t site  clustersite installloc="/install"

For IPMI controlled nodes, if you want the out-of-band IPMI operations to be 
done directly from the management node (instead of being sent to the 
appropriate service node), set site.ipmidispatch=n.

If you want to throttle the rate at which nodes are booted up, you can set the 
following site attributes:


* syspowerinterval
* syspowermaxnodes
* powerinterval (system p only)

See the `site table man page <http://localhost/fack_todo>`_ for details.

.. _setup_networks_table_label:

Setup networks Table
--------------------

All networks in the cluster must be defined in the networks table. When xCAT 
is installed, it runs makenetworks, which creates an entry in the networks
table for each of the networks the management node is on. You need to add
entries for each network the service nodes use to communicate to the compute
nodes.

For example: ::

  mkdef -t network net1 net=10.5.1.0 mask=255.255.255.224 gateway=10.5.1.1

If you want to set the nodes' xcatmaster as the default gateway for the nodes, 
the gateway attribute can be set to keyword "<xcatmaster>". In this case, xCAT 
code will automatically substitute the IP address of the node's xcatmaster for 
the keyword. Here is an example:
::

  mkdef -t network net1 net=10.5.1.0 mask=255.255.255.224 gateway=<xcatmaster>

The ipforward attribute should be enabled on all the xcatmaster nodes that 
will be acting as default gateways. You can set ipforward to 1 in the 
servicenode table or add the line "net.ipv4.ip_forward = 1" in file 
``/etc/sysctl.conf`` and then run "sysctl -p /etc/sysctl.conf" manually to
enable the ipforwarding.

Note:If using service node pools, the networks table dhcpserver attribute can 
be set to any single service node in your pool. The networks tftpserver, and 
nameserver attributes should be left blank.

Verify the Tables
--------------------

To verify that the tables are set correctly, run lsdef on the service nodes,
compute1, compute2: ::

  lsdef service,compute1,compute2

Add additional adapters configuration script (optional)
------------------------------------------------------------

It is possible to have additional adapter interfaces automatically configured 
when the nodes are booted. XCAT provides sample configuration scripts for 
ethernet, IB, and HFI adapters. These scripts can be used as-is or they can be 
modified to suit your particular environment. The ethernet sample is 
``/install/postscript/configeth``. When you have the configuration script that
you want you can add it to the "postscripts" attribute as mentioned above. Make
sure your script is in the ``/install/postscripts`` directory and that it is
executable.

Note: For system p servers, if you plan to have your service node perform the 
hardware control functions for its compute nodes, it is necessary that the SN 
ethernet network adapters connected to the HW service VLAN be configured.

Configuring Secondary Adapters
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To configure secondary adapters, see `Configuring_Secondary_Adapters
<http://localhost/fake_todo>`_


