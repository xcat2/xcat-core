Large Clusters
==============

When managing large clusters, it is recommended to have more than one node (Management Node, "MN") handling the installation and management of all the compute nodes.  These additional "helper" nodes are called **Service Nodes** ("SN").  The Management Node can delegate all management operational needs for a compute node to the Service Node responsible for that compute node.  There can be one or more Service Nodes configured to install/manage a group of compute nodes. 

The following configurations are supported by xCAT:

    * Each Service Node installs/manages a specific set of compute nodes
    * Having a pool of Service Nodes in which any can respond to an installation request from a compute node 
    * A hybrid of the above, where each specific set of compute nodes have 2 or more Service Nodes in a pool


.. toctree::
   :maxdepth: 2

   service_nodes/service_nodes101.rst
   databases/index.rst
   service_nodes/define_service_nodes.rst
   service_nodes/provision_service_nodes.rst
   tips.rst
