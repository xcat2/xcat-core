Overview
========

XCAT supports the concept of zones within a single xCAT cluster managed by one Management Node.  The nodes in the cluster can be divided up into multiple zones that have different ssh keys managed separately. 

Each defined zone has it own root's ssh RSA keys, so that any node can ssh without a password to any other node in the same zone,  cannot ssh without being prompted for a password to nodes in another zone.

Currently xCAT changes root ssh keys on the service nodes (SN) and compute nodes (CN) that are generated at install time to the root ssh keys from the Management node. It also changes the ssh **hostkeys** on the SN and CN to a set of pre-generated hostkeys from the MN. Putting the RSA public key in the **authorized-keys** file on the service nodes and compute nodes allows passwordless ssh to the Service Nodes (SN) and the compute nodes from the Management Node (MN). Today, by default, all nodes in the xCAT cluster are setup to be able to passwordless ssh to other nodes except when using the site **sshbetweennodes** attribute. More on that later. The pre-generated hostkey makes all nodes look like the same to ssh, so you are never prompted for updates to ``known_hosts``.

The new support only addresses the way we generate and distribute root's ssh RSA keys. Hostkey generation and distribution is not affected. It only supports setting up zones for the root userid. Non-root users are not affected. The Management node (MN) and Service Nodes (SN) are still setup so that root can ssh without password to the nodes from the MN and SN's for xCAT command to work. Also, the SN's should be able to ssh to each other with a password. Compute nodes and Service Nodes are not setup by xCAT to be able to ssh to the Management Node without being prompted for a password. This is to protect the Management Node.

In the past, the setup allowed compute nodes to be able to ssh to the SN's without a password. Using zones, will no longer allow this to happen. Using zones only allows compute nodes to ssh without password to compute node, unless you add the service node into the zone which is not considered a good idea.

But add service node into a zone is not a good idea. Beacuse:

* IF you put the service node in a zone, it will no longer be able to ssh to the other servicenodes with being prompted for a password.
* Allowing the compute node to ssh to the service node, could allow the service node to be compromised, by anyone who gained access to the compute node.
* It is recommended to not put the service nodes in any zones and then they will use the default zone which today will assign the root's home directory ssh keys as in previous releases. More on the default zone later.

If you do not wish to use zones, your cluster will continue to work as before. The root ssh keys for the nodes will be taken from the Management node's root's home directory ssh keys or the Service node's root's home directory ssh keys (hierarchical case) and put on the nodes when installing, running ``xdsh -K`` or ``updatenode -k``. To continue to operate this way, do not define a zone. The moment you define a zone in the database, you will begin using zones in xCAT.

