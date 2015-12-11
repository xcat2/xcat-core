Hierarchical Clusters / Large Cluster Support
=============================================

xCAT supports management of very large sized cluster by creating a **Hierarchical Cluster** and the concept of **xCAT Service Nodes**.  

When dealing with large clusters, to balance the load, it is recommended to have more than one node (Management Node, "MN") handling the installation and management of the Compute Nodes ("CN").  These additional *helper* nodes are referred to as **Service Nodes** ("SN").  The Management Node can delegate all management operational needs to the Service Node responsible for a set of compute node.

The following configurations are supported:
    * Each service node installs/manages a specific set of compute nodes
    * Having a pool of service nodes, any of which can respond to an installation request from a compute node (*Requires service nodes to be aligned with networks broadcast domains, compute node chooses service nodes based on who responds to DHCP request first.*)
    * A hybrid of the above, where each specific set of compute nodes have 2 or more service nodes in a pool

The following documentation assumes an xCAT cluster has already been configured and covers the additional steps needed to support xCAT Hierarchy via Service Nodes.


.. toctree::
   :maxdepth: 2

   service_nodes.rst
   databases/index.rst
   define_service_nodes.rst
   configure_dhcp.rst
   provision/index.rst
   appendix/index.rst
