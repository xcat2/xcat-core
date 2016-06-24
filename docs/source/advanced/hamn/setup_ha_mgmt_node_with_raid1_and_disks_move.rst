.. _setup_ha_mgmt_node_with_raid1_and_disks_move:

Setup HA Mgmt Node With RAID1 and disks move
============================================

This documentation illustrates how to setup a second management node, or standby management node, in your cluster to provide high availability management capability, using RAID1 configuration inside the management node and physically moving the disks between the two management nodes.

When one disk fails on the primary xCAT management node, replace the failed disk and use the RAID1 functionality to reconstruct the RAID1.

When the primary xCAT management node fails, the administrator can shutdown the failed primary management node, unplug the disks from the primary management node and insert the disks into the standby management node, power on the standby management node and then the standby management immediately takes over the cluster management role.

This HAMN approach is primarily intended for clusters in which the management node manages diskful nodes or linux stateless nodes. This also includes hierarchical clusters in which the management node only directly manages the diskful or linux stateless service nodes, and the compute nodes managed by the service nodes can be of any type.

If the compute nodes use only readonly nfs mounts from the MN management node, you can use this doc as long as you recognize that your nodes will go down while you are failing over to the standby management node. If the compute nodes depend on the management node being up to run its operating system over NFS, this doc is not suitable.

Configuration requirements
==========================

#. The hardware type/model are not required to be identical on the two management nodes, but it is recommended to use similar hardware configuration on the two management nodes, at least have similar hardware capability on the two management nodes to support the same operating system and have similar management capability.

#. Hardware RAID: Most of the IBM servers provide hardware RAID option, it is assumed that the hardware RAID configuration will be used in this HAMN configuration, if hardware RAID is not available on your servers, the software RAID MIGHT also work, but use it at your own risk.

#. The network connections on the two management nodes must be the same, the ethx on the standby management node must be connected to same network with the ethx on the primary management node.

#. Use router/switch for routing: if the nodes in the cluster need to connect to the external network through gateway, the gateway should be on the router/switch instead of the management node, the router/switch have their own redundancy.

Configuration procedure
=======================

Configure hardware RAID on the two management nodes
-----------------------------------------------------

Follow the server documentation to setup the hardware RAID1 on the standby management node first, and then move the disks to the primary management node, setup hardware RAID1 on the primary management node.

Install OS on the primary management node
------------------------------------------------

Install operating system on the primary management node using whatever method and configure the network interfaces.

Make sure the attribute **HWADDR** is not specified in the network interface configuration file, like ifcfg-eth0.

Initial failover test
----------------------

This is a sanity check, need to make sure the disks work on the two management nodes, just in case the disks do not work on the standby management node, we do not need to redo too much. **DO NOT** skip this step.

Power off the primary management node, unplug the disks from the primary management node and insert them into the standby management node, boot up the standby management node and make sure the operating system is working correctly, and the network interfaces could connect to the network.

If there are more than one network interfaces managed by the same network driver, like ``e1000``, the network interfaces sequence might be different on the two management nodes even if the hardware configuration is identical on the two management nodes, you need to test the network connections during initial configuration to make sure it works.

It is unlikely to happen, but just in case the ip addresses on the management node are assigned by DHCP, make sure the DHCP server is configured to assign the same ip address to the network interfaces on the two management nodes.

After this, fail back to the primary management node, using the same procedure mentioned above.

Setup xCAT on the Primary Management Node
-------------------------------------------

Follow the doc :doc:`xCAT Install Guide <../../guides/install-guides/index>` to setup xCAT on the primary management node

Continue setting up the cluster
--------------------------------

You can now continue to setup your cluster. Return to using the primary management node. Now setup your cluster using the following documentation, depending on your Hardware,OS and type of install you want to do on the Nodes :doc:`Admin Guide <../../guides/admin-guides/index>`.

For all the xCAT docs: http://xcat-docs.readthedocs.org

During the cluster setup, there is one important thing to consider:

**Network services on management node**

Avoid using the management node to provide network services that are needed to be run continuously, like DHCP, named, ntp, put these network services on the service nodes if possible, multiple service nodes can provide network services redundancy, for example, use more than one service nodes as the name servers, DHCP servers and ntp servers for each compute node; if there is no service node configured in the cluster at all, static configuration on the compute nodes, like static ip address and /etc/hosts name resolution, can be used to eliminate the dependency with the management node.

Failover
========

The failover procedure is simple and straightforward:

#. Shutdown the primary management node

#. Unplug the disks from the primary management node, insert these disks into the standby management node

#. Boot up the standby management node

#. Verify the standby management node could now perform all the cluster management operations. 
