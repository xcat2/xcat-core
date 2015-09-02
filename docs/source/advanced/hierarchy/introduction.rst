Introduction
============

In large clusters, it is desirable to have more than one node (the Management
Node - MN) handle the installation and management of the compute nodes. We 
call these additional nodes **service nodes (SN)**. The management node can
delegate all management operations needed by a compute node to the SN that is
managing that compute node. You can have one or more service nodes setting up
to install and manage groups of compute nodes.

Service Nodes
-------------

With xCAT, you have the choice of either having each service node 
install/manage a specific set of compute nodes, or having a pool of service 
nodes, any of which can respond to an installation request from a compute 
node. (Service node pools must be aligned with the network broadcast domains, 
because the way a compute node choose its SN for that boot is by whoever 
responds to the DHCP request broadcast first.) You can also have a hybrid of
the 2 approaches, in which for each specific set of compute nodes you have 2 
or more SNs in a pool.

Each SN runs an instance of xcatd, just like the MN does. The xcatd daemons
communicate with each other using the same XML/SSL protocol that the xCAT 
client uses to communicate with xcatd on the MN.

Daemon-based Databases
----------------------

The service nodes need to communicate with the xCAT database on the Management 
Node. They do this by using the remote client capability of the database (i.e. 
they don't go through xcatd for that). Therefore the Management Node must be 
running one of the daemon-based databases supported by xCAT (PostgreSQL, 
MySQL).

The default SQLite database does not support remote clients and cannot be used 
in hierarchical clusters. This document includes instructions for migrating 
your cluster from SQLite to one of the other databases. Since the initial 
install of xCAT will always set up SQLite, you must migrate to a database that 
supports remote clients before installing your service nodes.

Setup
-----
xCAT will help you install your service nodes as well as install on the SNs
xCAT software and other required rpms such as perl, the database client, and
other pre-reqs. Service nodes require all the same software as the MN
(because it can do all of the same functions), except that there is a special
top level xCAT rpm for SNs called xCATsn vs. the xCAT rpm that is on the
Management Node. The xCATsn rpm tells the SN that the xcatd on it should
behave as an SN, not the MN.
