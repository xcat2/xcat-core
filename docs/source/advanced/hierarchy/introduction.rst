Introduction
============

When dealing with large clusters, it is desirable to have more than one node,
the xCAT Management Node (MN), handle the installation and management of the 
Com[pute Nodes (CN).  The concept of these additional "helper" nodes are called
**Service Nodes (SN)**.  The Management Node can delegate all management 
operations required by a compute node to the service node that is assigned to 
manage that Compute Node. You can configure one or more Service Nodes to install
and manage a group of Compute Nodes.

Service Nodes
-------------

With xCAT, you have the choice of either having each Service Node 
install/manage a specific set of compute nodes, or having a pool of Service 
Nodes, any of which can respond to an installation request from a compute 
node. (Service Node pools must be aligned with the network broadcast domains, 
because the way a compute node choose its Service Node for that boot is by whoever 
responds to the DHCP request broadcast first.) You can also have a hybrid of
the 2 approaches, in which for each specific set of compute nodes you have 2 
or more Service Nodes in a pool.

Each Service Node runs an instance of xcatd, just like the Management Node does. 
The ``xcatd`` daemons communicate with each other using the same XML/SSH protocol
that the xCAT clients use to communicate with ``xcatd`` on the Management Node. 

Daemon-based Databases
----------------------

The Service Nodes will need to communicate with the xCAT database on the Management 
Node and do this by using the remote client capabilities of the database.  Therefore,
the Management Node must be running one of the daemon-based databases supported by 
xCAT (PostgreSQL, MySQL, MariaDB, etc). 

The default SQLite database does not support remote clients and cannot be used 
in hierarchical clusters. This document includes instructions for migrating 
your cluster from SQLite to one of the other databases. Since the initial 
install of xCAT will always set up SQLite, you must migrate to a database that 
supports remote clients before installing your Service Nodes.

Setup
-----
xCAT will help you install your Service Nodes as well as install on the xCAT-SN
software and other required rpms and pre-reqs.  Service Nodes require the same 
software as installed on the Management Node with the exception of the top level
xCAT rpm.  The Management Node installs the ``xCAT`` package while the Service Nodes
install the ``xCATsn`` package. 
