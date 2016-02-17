
###############
nodechprofile.1
###############

.. highlight:: perl


****
NAME
****


\ **nodechprofile**\  - updates a profile used by a node


********
SYNOPSIS
********


\ **nodechprofile**\  \ **[-h| -**\ **-help | -v | -**\ **-version]**\ 

\ **nodechprofile**\  \ *noderange*\  [\ **imageprofile=**\  \ *image-profile*\ ] [\ **networkprofile=**\  \ *network-profile*\ ] [\ **hardwareprofile=**\  \ *hardware-profile*\ ]


***********
DESCRIPTION
***********


The \ **nodechprofile**\  command updates the profiles used by a node, including: the image profile, network profile, and hardware management profile.

If you update the image profile for a node, the operating system and provisioning settings for the node are updated.

If you update the network profile, the IP address and network settings for the node are updated.

If you update the hardware management profile, the hardware settings for the node are updated.

After nodes' hardware profile or image profile are updated, the status for each node is changed to "defined". A node with a "defined" status must be reinstalled

After nodes' network profile updated, the status for nodes is not changed. You'll need to run \ **noderegenips**\  to re-generate the nodes' IP address and nodes' status may also be updated at this stage.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.

\ *noderange*\ 

The nodes to be removed.

\ **imageprofile=**\  \ *image-profile*\ 

Sets the new image profile name used by the node, where <image-profile> is the new image profile.  An image profile defines the provisioning method, OS information, kit information, and provisioning parameters for a node. If the "__ImageProfile_imgprofile" group already exists in the nodehm table, then "imgprofile" is used as the image profile name.

\ **networkprofile=**\  \ *network-profile*\ 

Sets the new network profile name used by the node, where <network-profile> is the new network profile. A network profile defines the network, NIC, and routes for a node. If the "__NetworkProfile_netprofile" group already exists in the nodehm table, then "netprofile" is used as the network profile name.

\ **hardwareprofile=**\  \ *hardware-profile*\ 

Sets the new hardware profile name used by the node, where <hardware-profile> is the new hardware management profile used by the node. If a "__HardwareProfile_hwprofile" group exists, then "hwprofile" is the hardware profile name. A hardware profile defines hardware management related information for imported nodes, including: IPMI, HMC, CEC, CMM.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********



1. To change the image profile to rhels6.3_packaged for compute nodes compute-000 and compute-001, use the following command:
 
 
 .. code-block:: perl
 
   nodechprofile compute-000,compute-001 imageprofile=rhels6.3_packaged
 
 


2. To change all of the profiles for compute node compute-000, enter the following command:
 
 
 .. code-block:: perl
 
   nodechprofile compute-000 imageprofile=rhels6.3_packaged networkprofile=default_cn hardwareprofile=default_ipmi
 
 



********
SEE ALSO
********


nodepurge(1)|nodepurge.1, noderefresh(1)|noderefresh.1, nodeimport(1)|nodeimport.1, noderange(3)|noderange.3

