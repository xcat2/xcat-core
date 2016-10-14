High Availability
=================

The xCAT management node plays an important role in the cluster, if the management node is down for whatever reason, the administrators will lose the management capability for the whole cluster, until the management node is back up and running. In some configurations, like the Linux NFSROOT-based statelite in a non-hierarchy cluster, the compute nodes may not be able to run at all without the management node. So, it is important to consider the high availability for the management node.

The goal of the HAMN (High Availability Management Node) configuration is, when the primary xCAT management node fails, the standby management node can take over the role of the management node, either through automatic failover or through manual procedure performed by the administrator, and thus avoid long periods of time during which your cluster does not have active cluster management function available.


The following pages describes ways to configure the xCAT Management Node for High Availability. 

.. toctree::
   :maxdepth: 2

   high_available_management_node.rst
