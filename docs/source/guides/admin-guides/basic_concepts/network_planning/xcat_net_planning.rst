xCAT Network Planning
=====================

Before setting up your cluster, there are a few things that are important to think through first, because it is much easier to go in the direction you want right from the beginning, instead of changing course midway through.

Do You Need Hierarchy in Your Cluster?
--------------------------------------

Service Nodes
`````````````
For very large clusters, xCAT has the ability to distribute the management operations to service nodes. This allows the management node to delegate all management responsibilities for a set of compute or storage nodes to a service node so that the management node doesn't get overloaded. Although xCAT automates a lot of the aspects of deploying and configuring the services, it still adds complexity to your cluster. So the question is: at what size cluster do you need to start using service nodes? The exact answer depends on a lot of factors (mgmt node size, network speed, node type, OS, frequency of node deployment, etc.), but here are some general guidelines for how many nodes a single management node (or single service node) can handle:

* **[Linux]:**
        * Stateful or Stateless: 500 nodes
        * Statelite: 250 nodes
* **[AIX]:** 
        150 nodes

These numbers can be higher (approximately double) if you are willing to "stage" the more intensive operations, like node deployment.

Of course, there are some reasons to use service nodes that are not related to scale, for example, if some of your nodes are far away (network-wise) from the mgmt node.

Network Hierarchy
`````````````````
For large clusters, you may want to divide the management network into separate subnets to limit the broadcast domains. (Service nodes and subnets don't have to coincide, although they often do.) xCAT clusters as large as 3500 nodes have used a single broadcast domain.

Some cluster administrators also choose to sub-divide the application interconnect to limit the network contention between separate parallel jobs.


Design an xCAT Cluster for High Availability
--------------------------------------------

Everyone wants their cluster to be as reliable and available as possible, but there are multiple ways to achieve that end goal. Availability and complexity are inversely proportional. You should choose an approach that balances these 2 in a way that fits your environment the best. Here's a few choices in order of least complex to more complex.

**Service Node Pools** With No HA Software
``````````````````````````````````````````
**Service node pools** is an xCAT approach in which more than one service node (SN) is in the broadcast domain for a set of nodes. When each node netboots, it chooses an available SN by which one responds to its DHCP request 1st. When services are set up on the node (e.g. DNS), xCAT configures the services to use at that SN and one other SN in the pool. That way, if one SN goes down, the node can keep running, and the next time it netboots it will automatically choose another SN.

This approach is most often used with stateless nodes because that environment is more dynamic. It can possibly be used with stateful nodes (with a little more effort), but that type of node doesn't netboot nearly as often so a more manual operation (snmove) is needed in that case move a node to different SNs.

It is best to have the SNs be as robust as possible, for example, if they are diskful, configure them with at least 2 disks that are RAID'ed together.

In smaller clusters, the management node (MN) can be part of the SN pool with one other SN.

In larger clusters, if the network topology dictates that the MN is only for managing the SNs (not the compute nodes), then you need a plan for what to do if the MN fails. Since the cluster can continue to run if the MN is down temporarily, the plan could be as simple as have a backup MN w/o any disks. If the primary MN fails, move its RAID'ed disks to the backup MN and power it on.

HA Management Node
``````````````````

If you want to use HA software on your management node to synchronize data and fail over services to a backup MN, see [TODO Highly_Available_Management_Node], which discusses the different options and the pros and cons.

It is important to note that some HA-related software like DRDB, Pacemaker, and Corosync is not officially supported by IBM, meaning that if you have a problem specifically with that software, you will have to go to the open source community or another vendor to get a fix.

HA Service Nodes
````````````````

When you have NFS-based diskless (statelite) nodes, there is sometimes the motivation make the NFS serving highly available among all of the service nodes. This is not recommended because it is a very complex configuration. In our opinion, the complexity of this setup can nullify much of the availability you hope to gain. If you need your compute nodes to be highly available, you should strongly consider stateful or stateless nodes.

If you still have reasons to pursue HA service nodes:

*   For **[AIX]** , see [TODO XCAT_HASN_with_GPFS]
*   For **[Linux]** , a couple prototype clusters have been set up in which the NFS service on the SNs is provided by GPFS CNFS (Clustered NFS). A howto is being written to describe the setup as an example. Stay tuned.
 
