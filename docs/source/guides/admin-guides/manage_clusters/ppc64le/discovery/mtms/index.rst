MTMS-based Discovery
====================

MTMS stands for  **M**\ achine  **T**\ ype/\ **M**\ odel and **S**\ erial.  This is one way to uniquely identify each physical server.  

MTMS-based hardware discovery assumes the administator has the model type and serial number information for the physical servers and a plan for mapping the servers to intended hostname/IP addresses.

**Overview**

   #. Automatically search and collect MTMS information from the servers
   #. Write **discovered-bmc-nodes** to xCAT (recommened to set different BMC IP address)
   #. Create **predefined-compute-nodes** to xCAT providing additional properties
   #. Power on the nodes which triggers xCAT hardware discovery engine

**Pros**

   * Limited effort to get servers defined using xCAT hardware discovery engine

**Cons**

   * When compared to switch-based discovery, the administrator needs to create the **predefined-compute-nodes** for each of the **discovered-bmc-nodes**.  This could become difficult for a large number of servers.

.. toctree::
   :maxdepth: 2

   verification.rst
   discovery.rst 
