Overview
--------

Synchronizing (sync) files to the nodes is a feature of xCAT used to distribute specific files from the management node to the new-deploying or deployed nodes.

This function is supported for diskful or RAMdisk-based diskless nodes.Generally, the specific files are usually the system configuration files for the nodes in the **/etc/directory**, like **/etc/hosts**, **/etc/resolve.conf**; it also could be the application programs configuration files for the nodes. The advantages of this function are: it can parallel sync files to the nodes or nodegroup for the installed nodes; it can automatically sync files to the newly-installing node after the installation. Additionally, this feature also supports the flexible format to define the synced files in a configuration file, called **'synclist'**.

The synclist file can be a common one for a group of nodes using the same profile or osimage, or can be the special one for a particular node. Since the location of the synclist file will be used to find the synclist file, the common synclist should be put in a given location for Linux nodes or specified by the osimage.

``xdcp`` command supplies the basic Syncing File function. If the **'-F synclist'** option is specified in the ``xdcp`` command, it syncs files configured in the synclist to the nodes. If the **'-i PATH'** option is specified with **'-F synclist'**, it syncs files to the root image located in the PATH directory. (**Note: the '-i PATH' option is only supported for Linux nodes**)

``xdcp`` supports hierarchy where service nodes are used. If a node is serviced by a service node, ``xdcp`` will sync the files to the service node first, then sync the files from service node to the compute node. The files are place in an intermediate directory on the service node defined by the SNsyncfiledir attribute in the site table. The default is **/var/xcat/syncfiles**.

Since ``updatenode -F`` calls the ``xdcp`` to handle the Syncing File function, the ``updatenode -F`` also supports the hierarchy.

For a new-installing nodes, the Syncing File action will be triggered when performing the postscripts for the nodes. A special postscript named **'syncfiles'** is used to initiate the Syncing File process.

The postscript **'syncfiles'** is located in the **/install/postscripts/**. When running, it sends a message to the xcatd on the management node or service node, then the xcatd figures out the corresponding synclist file for the node and calls the ``xdcp`` command to sync files in the synclist to the node.

**If installing nodes in a hierarchical configuration, you must sync the Service Nodes first to make sure they are updated. The compute nodes will be sync'd from their service nodes.You can use the** ``updatenode <computenodes> -f`` **command to sync all the service nodes for range of compute nodes provided.**

For an installed nodes, the Syncing File action happens when performing the ``updatenode -F`` or ``xdcp -F synclist`` command to update a nodes. If performing the ``updatenode -F``, it figures out the location of the synclist files for all the nodes and classify the nodes which using same synclist file and then calls the ``xdcp -F synclist`` to sync files to the nodes.


