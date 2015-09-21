Networks in an xCAT Cluster
===========================

The networks that are typically used in a cluster are:

Management network 
------------------
used by the management node to install and manage the OS of the nodes. The MN and in-band NIC of the nodes are connected to this network. If you have a large cluster with service nodes, sometimes this network is segregated into separate VLANs for each service node.

Service network
---------------
used by the management node to control the nodes out of band via the BMC. If the BMCs are configured in shared mode [1]_, then this network can be combined with the management network.

Application network 
------------------- 
used by the HPC applications on the compute nodes. Usually an IB network.

Site (Public) network
--------------------- 
used to access the management node and sometimes for the compute nodes to provide services to the site.


.. [1] shared mode: In "Shared" mode, the BMC network interface and the in-band network interface will share the same network port.
