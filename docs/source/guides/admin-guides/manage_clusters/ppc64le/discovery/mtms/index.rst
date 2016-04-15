MTMS-based Discovery
====================

MTMS stands for  **M**\ achine  **T**\ ype/\ **M**\ odel and **S**\ erial.  This is one way to uniquely identify each physical server.  

MTMS-based hardware discovery assumes the administator has the model type and serial number information for the physical servers and a plan for mapping the servers to intended hostname/IP addresses.

**Overview**

   #. Automatically search and collect MTMS information from the servers
   #. Define the **discovered-node** to xCAT
   #. Create a **predefined-node** to xCAT providing additional properties
   #. Power on the **discovered-nodes** triggering xCAT's hardware discovery engine.

**Pros**

   * Limited effort to get servers defined using xCAT hardware discovery engine

**Cons**

   * When compared to switch-based discovery, the administrator needs to create the **predefined-node** for each of the **discovered-nodes** stanzas.  This could become difficult for a large number of servers.

.. toctree::
   :maxdepth: 2

   verification.rst
   discovery.rst 
