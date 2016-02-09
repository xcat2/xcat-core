MTMS-based Discovery
====================

MTMS is short for  **M**\ achine  **T**\ ype/\ **M**\ odel and **S**\ erial which is unique for each physical server.  MTMS-based hardware discovery assumes that the administator has the MTMS information for all the physical servers and has a mapping for the MTMS and hostname/IP for the servers.

Pros and Cons
-------------

Pros
````

   * Limited effort to get servers defined using xCAT hardware discovery engine

Cons
````

   * When compared to switch-based discovery, the administrator needs to be involved to create a **predefined-node** from each of the **discovered-nodes** stanzas.  This could become difficult for a large number of servers.


Overview
--------

   #. Automatically search and collect MTMS information from the servers
   #. Define the **discovered-node** to xCAT
   #. Create a **predefined-node** to xCAT providing additional properties
   #. Power on the **discovered-nodes** triggering xCAT's hardware discovery engine.


.. toctree::
   :maxdepth: 2

   preverification.rst
   example_environment.rst
   discovery.rst
