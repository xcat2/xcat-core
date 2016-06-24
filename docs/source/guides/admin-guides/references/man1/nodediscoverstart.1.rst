
###################
nodediscoverstart.1
###################

.. highlight:: perl


****
NAME
****


\ **nodediscoverstart**\  - starts the node discovery process


********
SYNOPSIS
********


\ **nodediscoverstart**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

\ **Sequential Discovery Specific:**\ 


\ **nodediscoverstart**\  \ **noderange=**\ \ *noderange*\  [\ **hostiprange=**\ \ *imageprofile*\ ] [\ **bmciprange=**\ \ *bmciprange*\ ] [\ **groups=**\ \ *groups*\ ] [\ **rack=**\ \ *rack*\ ] [\ **chassis=**\ \ *chassis*\ ] [\ **height=**\ \ *height*\ ] [\ **unit=**\ \ *unit*\ ] [\ **osimage=**\  \ *osimagename*\ >] [\ **-n | -**\ **-dns**\ ] [\ **-s | -**\ **-skipbmcsetup**\ ] [\ **-V|-**\ **-verbose**\ ]

\ **Profile Discovery Specific:**\ 


\ **nodediscoverstart**\  \ **networkprofile=**\ \ *network-profile*\  \ **imageprofile=**\ \ *image-profile*\  \ **hostnameformat=**\ \ *nost-name-format*\  [\ **hardwareprofile=**\ \ *hardware-profile*\ ] [\ **groups=**\ \ *node-groups*\ ] [\ **rack=**\ \ *rack-name*\ ] [\ **chassis=**\ \ *chassis-name*\ ] [\ **height=**\ \ *rack-server-height*\ ] [\ **unit=**\ \ *rack-server-unit-location*\ ] [\ **rank=**\ \ *rank-num*\ ]


***********
DESCRIPTION
***********


The \ **nodediscoverstart**\  command starts either the \ **Sequential Discovery**\  or \ **Profile Discovery**\  process.  They can not both be
running at the same time.

\ **Sequential Discovery Specific:**\ 


This is the simplest discovery approach.  You only need to specify the \ **noderange**\ , \ **hostiprange**\  and \ **bmciprange**\  that should be
given to nodes that are discovered.  (If you pre-define the nodes (via nodeadd or mkdef) and specify their host and BMC IP addresses,
then you only need to specify the \ **noderange**\  to the \ **nodediscoverstart**\  command.)  Once you have run \ **nodediscoverstart**\ , then
physically power on the nodes in the sequence that you want them to receive the node names and IPs, waiting a short time (e.g. 30 seconds)
between each node.

\ **Profile Discovery Specific:**\ 


This is the PCM discovery approach.  \ *networkprofile*\ , \ *imageprofile*\ , \ *hostnameformat*\  arguments must be specified to start the \ **Profile Discovery**\ .
All nodes discovered by this process will be associated with specified profiles and rack/chassis/unit locations.

When the nodes are discovered, PCM updates the affected configuration files on the management node automatically. Configuration files include the /etc/hosts service file, DNS configuration, and DHCP configuration. Kit plug-ins are automatically triggered to update kit related configurations and services.

When you power on the nodes, they PXE boot and DHCP/TFTP/HTTP on the management node give each node the xCAT genesis boot image,
which inventories the node hardware and sends data to the management node.  There, either the sequential discovery process or the
profile discovery process assigns node attributes and defines the node in the the database.


*******
OPTIONS
*******



\ **noderange=**\ \ *noderange*\ 
 
 The set of node names that should be given to nodes that are discovered via the \ **Sequential Discovery**\  method.
 This argument is required to \ **Sequential Discovery**\ . Any valid xCAT \ **noderange**\  is allowed, e.g. node[01-10].
 


\ **hostiprange=**\ \ *ip range*\ 
 
 The ip range which will be assigned to the host of new discovered nodes in the \ **Sequential Discovery**\  method. The format can be: \ *start_ip*\ \ **-**\ \ *end_ip*\  or \ *noderange*\ , e.g. 192.168.0.1-192.168.0.10 or 192.168.0.[1-10].
 


\ **bmciprange=**\ \ *ip range*\ 
 
 The ip range which will be assigned to the bmc of new discovered nodes in the \ **Sequential Discovery**\  method. The format can be: \ *start_ip*\ \ **-**\ \ *end_ip*\  or \ *noderange*\ , e.g. 192.168.1.1-192.168.1.10 or 192.168.1.[1-10].
 


\ **imageprofile=**\ \ *image-profile*\ 
 
 Sets the new image profile name used by the discovered nodes in the \ **Profile Discovery**\  method.  An image profile defines the provisioning method, OS information, kit information, and provisioning parameters for a node. If the "__ImageProfile_imgprofile" group already exists in the nodehm table, then "imgprofile" is used as the image profile name.
 


\ **networkprofile=**\ \ *network-profile*\ 
 
 Sets the new network profile name used by the discovered nodes in the \ **Profile Discovery**\  method. A network profile defines the network, NIC, and routes for a node. If the "__NetworkProfile_netprofile" group already exists in the nodehm table, then "netprofile" is used as the network profile name.
 


\ **hardwareprofile=**\ \ *hardware-profile*\ 
 
 Sets the new hardware profile name used by the discovered nodes in the \ **Profile Discovery**\  method. If a "__HardwareProfile_hwprofile" group exists, then "hwprofile" is the hardware profile name. A hardware profile defines hardware management related information for imported nodes, including: IPMI, HMC, CEC, CMM.
 


\ **hostnameformat=**\ \ *nost-name-format*\ 
 
 Sets the node name format for all discovered nodes in the \ **Profile Discovery**\  method. The two types of formats supported are prefix#NNNappendix and prefix#RRand#NNappendix, where wildcard #NNN and #NN are replaced by a system generated number that is based on the provisioning order. Wildcard #RR represents the rack number and stays constant.
 
 For example, if the node name format is compute-#NN, the node name is generated as: compute-00, compute-01, ..., compute-99. If the node name format is blade#NNN-x64, the node name is generated as: blade001-x64, blade002-x64, ..., blade999-x64
 
 For example, if the node name format is compute-#RR-#NN and the rack number is 2, the node name is generated as: compute-02-00, compute-02-01, ..., compute-02-99. If node name format is node-#NN-in-#RR and rack number is 1, the node name is generated as: node-00-in-01, node-01-in-01, ..., node-99-in-01
 


\ **groups=**\ \ *node-groups*\ 
 
 Sets the node groups that the discovered nodes should be put in for either the Sequential Discovery or Profile Discovery methods, where \ *node-group*\  is a comma-separated list of node groups.
 


\ **rack=**\ \ *rack-name*\ >
 
 Sets the rack name where the node is located for either the Sequential Discovery or Profile Discovery methods.
 


\ **chasiss=**\ \ *chassis-name*\ 
 
 Sets the chassis name that the Blade server or PureFlex blade is located in, for either the Sequential Discovery or Profile Discovery methods. This option is used for the Blade server and PureFlex system only. You cannot specify this option with the rack option.
 


\ **height=**\ \ *rack-server-height*\ 
 
 Sets the height of a rack-mounted server in U units for either the Sequential Discovery or Profile Discovery methods. If the rack option is not specified, the default value is 1.
 


\ **unit=**\ \ *rack-server-unit-location*\ 
 
 Sets the start unit value for the node in the rack, for either the Sequential Discovery or Profile Discovery methods. This option is for a rack server only. If the unit option is not specified, the default value is 1
 


\ **rank=**\ \ *rank-num*\ 
 
 Specifies the starting rank number that is used in the node name format, for the Profile Discovery method.  The rank number must be a valid integer between 0 and 254. This option must be specified with nodenameformat option. For example, if your node name format is compute-#RR-#NN. The rack's number is 2 and rank is specified as 5, the node name is generated as follows: compute-02-05, compute-02-06, ..., compute-02-99.
 


\ **osimage=**\ \ *osimagename*\ 
 
 Specifies the osimage name that will be associated with the new discovered node, the os provisioning will be started automatically at the end of the discovery process.
 


\ **-n|-**\ **-dns**\ 
 
 Specifies to run makedns <nodename> for any new discovered node. This is useful mainly for non-predefined configuration, before running the "nodediscoverstart -n", the user needs to run makedns -n to initialize the named setup on the management node.
 


\ **-s|-**\ **-skipbmcsetup**\ 
 
 Specifies to skip the bmcsetup during the sequential discovery process, if the bmciprange is specified with nodediscoverstart command, the BMC will be setup automatically during the discovery process, if the user does not want to run bmcsetup, could specify the "-s|--skipbmcsetup" with nodediscoverstart command to skip the bmcsetup.
 


\ **-V|-**\ **-verbose**\ 
 
 Enumerates the free node names and host/bmc ips that are being specified in the ranges given.  Use this option
 with Sequential Discovery to ensure that you are specifying the ranges you intend.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********



1. \ **Sequential Discovery**\ : To discover nodes with noderange and host/bmc ip range:
 
 
 .. code-block:: perl
 
   nodediscoverstart noderange=n[1-10] hostiprange='172.20.101.1-172.20.101.10' bmciprange='172.20.102.1-172.20.102.10' -V
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Sequential Discovery: Started:
      Number of free node names: 10
      Number of free host ips: 10
      Number of free bmc ips: 10
   ------------------------------------Free Nodes------------------------------------
   NODE                HOST IP             BMC IP
   n01                 172.20.101.1        172.20.102.1
   n02                 172.20.101.2        172.20.102.2
   ...                 ...                 ...
 
 


2. \ **Profile Discovery**\ : To discover nodes using the default_cn network profile and the rhels6.3_packaged image profile, use the following command:
 
 
 .. code-block:: perl
 
   nodediscoverstart networkprofile=default_cn imageprofile=rhels6.3_packaged hostnameformat=compute#NNN
 
 



********
SEE ALSO
********


nodediscoverstop(1)|nodediscoverstop.1, nodediscoverls(1)|nodediscoverls.1, nodediscoverstatus(1)|nodediscoverstatus.1

