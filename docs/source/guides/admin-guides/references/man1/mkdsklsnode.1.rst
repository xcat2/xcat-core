
#############
mkdsklsnode.1
#############

.. highlight:: perl


****
NAME
****


\ **mkdsklsnode**\  - Use this xCAT command to define and initialize AIX/NIM diskless machines.


********
SYNOPSIS
********


\ **mkdsklsnode [-h|-**\ **-help ]**\ 

\ **mkdsklsnode [-V|-**\ **-verbose] [-f|-**\ **-force] [-n|-**\ **-newname] [-i**\  \ *osimage_name*\ ] [\ **-l**\  \ *location*\ ] [\ **-u | -**\ **-updateSN**\ ] [\ **-k | -**\ **-skipsync**\ ] [\ **-p | -**\ **-primarySN**\ ] [\ **-b | -**\ **-backupSN**\ ] [\ **-S | -**\ **-setuphanfs**\ ] \ *noderange*\  [\ *attr=val [attr=val ...]*\ ]


***********
DESCRIPTION
***********


This xCAT command can be used to define and/or initialize AIX/NIM diskless machines. Once this step is completed you can use either the xCAT \ **rnetboot**\  command or the \ **rbootseq/rpower**\  commands to initiate a network boot of the nodes.

The command can be used to define and initialize a new NIM machine object or it can be used to reinitialize an existing machine to use a different operating system image.

This command will also create a NIM resolv_conf resource to be used when installing the node.  If a resolv_conf resource is not already included in the xCAT osimage definition and if the "domain" and "nameservers" values are set then a new NIM resolv_conf resource will be created and allocated to the nodes.

The "domain" and "nameservers" attributes can be set in either the xCAT "network" definition used by the nodes or in the xCAT cluster "site" definition. The setting in the "network" definition will take priority.

The "search" field of the resolv.conf file will contain a list all the domains 
listed in the xCAT network definitions and the xCAT site definiton.

The "nameservers" value can either be set to a specific IP address or the "<xcatmaster>" key word.  The "<xcatmaster>" key word means that the value of the "xcatmaster" attribute of the node definition will be used in the /etc/resolv.conf file.  (I.e.  The name of the install server as known by the node.)

You can set the "domain" and "nameservers" attributes by using the \ **chdef**\  command.  For example:


chdef -t network -o clstr_net domain=cluster.com nameservers=<xcatmaster>

If the "domain" and "nameservers" attributes are not set in either the nodes "network" definition or the "site" definition then no new NIM resolv_conf resource will be created.

If you are using xCAT service nodes the \ **mkdsklsnode**\  command will automatically determine the correct server(s) for the node and create the NIM definitions on that server(s).

When creating a new NIM machine definition the default is to use the same name as the xCAT node name that is provided.

You can use the "-n" option of the mkdsklsnode command to create and initialize an alternate NIM machine definition for the same physical nodes. This option allows you to set up a new image to use when a node is next rebooted while the node is currently running.  This is possible because the NIM name for a machine definition does not have to be the hostname of the node.  This allows you to have multiple NIM machine definitions for the same physical node. The naming convention for the new NIM machine name is "<xcat_node_name>_<image_name>", (Ex. "node01_61spot"). Since all the NIM initialization can be done while the node is running the downtime for for the node is reduced to the time it takes to reboot.

\ **Note:**\  When using the "-n" option make sure that the new osimage you specify and all the NIM resources that are used are different than what are currently being used on the nodes.  The NIM resources should not be shared between the old osimage and the new osimage.

You can use the force option to reinitialize a node if it already has resources allocated or it is in the wrong NIM state. This option will reset the NIM node and deallocate resources before reinititializing. Use this option with caution since reinitializing a node will stop the node if it is currently running.

After the mkdsklsnode command completes you can use the \ **lsnim**\  command to check the NIM node definition to see if it is ready for booting the node. ("lsnim -l <nim_node_name>").

You can supply your own scripts to be run on the management node  or on the service node (if their is hierarchy) for a node during the \ **mkdsklsnode**\  command. Such scripts are called \ **prescripts**\ . They should be copied to /install/prescripts dirctory. A table called \ *prescripts*\  is used to specify the scripts and their associated actions. The scripts to be run at the beginning of the \ **mkdsklsnode**\  command are stored in the 'begin' column of \ *prescripts*\  table. The scripts to be run at the end of the \ **mkdsklsnode**\  command are stored in the 'end' column of \ *prescripts*\  table. Please run 'tabdump prescripts -d' command for details. An example for the 'begin' or the 'end' column is: \ *diskless:myscript1,myscript2*\ . The following two environment variables will be passed to each script: NODES contains all the names of the nodes that need to run the script for and ACTION contains the current current nodeset action, in this case "diskless". If \ *#xCAT setting:MAX_INSTANCE=number*\  is specified in the script, the script will get invoked for each node in parallel, but no more than \ *number*\  of instances will be invoked at at a time. If it is not specified, the script will be invoked once for all the nodes.


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=
 val pairs must be specified last on the command line. These are used to specify additional values that can be passed to the underlying NIM commands.
 
 Valid values:
 
 
 \ **duplex**\ 
  
  Specifies the duplex setting (optional). Used when defining the NIM machine. Use this setting to configure the client's network interface. This value can be full or half. The default is full. (ex. "duplex=full")
  
 
 
 \ **speed**\ 
  
  Specifies the speed setting (optional). Used when defining the NIM machine. This is the communication speed to use when configuring the client's network interface. This value can be 10, 100, or 1000. The default is 100. (ex. "speed=100")
  
 
 
 \ **psize**\ 
  
  Specifies the size in Megabytes of the paging space for the diskless node.(optional) Used when initializing the NIM machine. The minimum and default size is 64 MB of paging space. (ex. "psize=256")
  
 
 
 \ **sparse_paging**\ 
  
  Specifies that the paging file should be created as an AIX sparse file, (ex. "sparse_paging=yes").  The default is "no".
  
 
 
 \ **dump_iscsi_port**\ 
  
  The tcpip port number to use to communicate dump images from the client to the dump	resource server. Normally set by default. This port number is used by a dump resource server.
  
 
 
 \ **configdump**\ 
  
  Specifies the type dump to be collected from the client.  The values are
  "selective", "full", and "none".  If the configdump attribute is set to "full"
  or "selective" the client will automatically be configured to dump to an iSCSI
  target device. The "selective" memory dump will avoid dumping user data. The
  "full" memory dump will dump all the memory of the client partition. Selective
  and full memory dumps will be stored in subdirectory of the dump resource
  allocated to the client. This attribute is saved in the xCAT osimage
  definition.
  
 
 


\ **-b |-**\ **-backupSN**\ 
 
 When using backup service nodes only update the backup.  The default is to update both the primary and backup service nodes.
 


\ **-f |-**\ **-force**\ 
 
 Use the force option to reinitialize the NIM machines.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-i**\  \ *image_name*\ 
 
 The name of an existing xCAT osimage definition. If this information is not provided on the command line the code checks the node definition for the value of the "provmethod" attribute. If the "-i" value is provided on the command line then that value will be used to set the "provmethod" attribute of the node definitions.
 


\ **-k|-**\ **-skipsync**\ 
 
 Use this option to have the mkdsklsnode command skip the NIM sync_roots operation.  This option should only be used if you are certain that the shared_root resource does not have to be updated from the SPOT.  Normally, when the SPOT is updated, you should do a sync_roots on the shared_root resource.
 


\ **-l|-**\ **-location**\ 
 
 The directory location to use when creating new NIM resolv_conf resources. The default location is /install/nim.
 


\ **-n|-**\ **-newname**\ 
 
 Create a new NIM machine object name for the xCAT node. Use the naming convention "<xcat_node_name>_<image_name>" for the new NIM machine definition.
 


\ **-p|-**\ **-primarySN**\ 
 
 When using backup service nodes only update the primary.  The default is to update both the primary and backup service nodes.
 


\ **-S|-**\ **-setuphanfs**\ 
 
 Setup NFSv4 replication between the primary service nodes and backup service nodes to provide high availability NFS for the compute nodes. This option only exports the /install directory with NFSv4 replication settings, the data synchronization between the primary service nodes and backup service nodes needs to be taken care of through some mechanism.
 


\ **-u|-**\ **-updateSN**\ 
 
 Use this option if you wish to update the osimages but do not want to define or initialize the NIM client definitions. This option is only valid when the xCAT "site" definition attribute "sharedinstall" is set to either "sns" or "all".
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on additional supported formats.
 


\ **-V |-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1. Initialize an xCAT node named "node01" as an AIX diskless machine.  The xCAT osimage named "61spot" should be used to boot the node.
 
 
 .. code-block:: perl
 
   mkdsklsnode -i 61spot node01
 
 


2. Initialize all AIX diskless nodes contained in the xCAT node group called "aixnodes" using the image definitions pointed to by the "provmethod" attribute of the xCAT node definitions.
 
 
 .. code-block:: perl
 
   mkdsklsnode aixnodes
 
 


3. Initialize diskless node "clstrn29" using the xCAT osimage called "61dskls".  Also set the paging size to be 128M and specify the paging file be an AIX sparse file.
 
 
 .. code-block:: perl
 
   mkdsklsnode -i 61dskls clstrn29 psize=128 sparse_paging=yes
 
 


4.
 
 Initialize an xCAT node called "node02" as an AIX diskless node.  Create a new NIM machine definition name with the osimage as an extension to the xCAT node name.
 
 
 .. code-block:: perl
 
   mkdsklsnode -n -i 61spot node02
 
 



*****
FILES
*****


/opt/xcat/bin/mkdsklsnode


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


rmdsklsnode(1)|rmdsklsnode.1

