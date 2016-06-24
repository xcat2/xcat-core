
############
nimnodeset.1
############

.. highlight:: perl


****
NAME
****


\ **nimnodeset**\  - Use this xCAT command to initialize AIX/NIM standalone machines.


********
SYNOPSIS
********


\ **nimnodeset [-h|-**\ **-help ]**\ 

\ **nimnodeset [-V|-**\ **-verbose] [-f|-**\ **-force] [-i**\  \ *osimage_name*\ ] [\ **-l**\  \ *location*\ ] [\ **-p|-**\ **-primarySN**\ ] [\ **-b | -**\ **-backupSN**\ ] \ *noderange [attr=val [attr=val ...]]*\ 


***********
DESCRIPTION
***********


This xCAT command can be used to initialize AIX/NIM standalone machines. Once this step is completed the either the xCAT \ **rnetboot**\  command or the \ **rbootseq/rpower**\  commands to initiate a network boot of the nodes.

If you are using xCAT service nodes the \ **nimnodeset**\  command will automatically determine the correct server(s) for the node and do the initialization on that server(s).

The osimage_name is the name of an xCAT osimage definition that contains the list of NIM resources to use when initializing the nodes.   If the osimage_name is not provided on the command line the code checks the node definition for the value of the "provmethod" attribute (which is the name of an osimage definition). If the osimage_image is provided on the command line then the code will also set the "provmethod" attribute of the node definiions.

This command will also create a NIM resolv_conf resource to be used when installing the node.  If a resolv_conf resource is not already included in the xCAT osimage definition and if the "domain" and "nameservers" values are set then a new
NIM resolv_conf resource will be created and allocated to the nodes.

The "domain" and "nameservers" attributes can be set in either the xCAT "network" definition used by the nodes or in the xCAT cluster "site" definition. The setting in the "network" definition will take priority.

The "search" field of the resolv.conf file will contain a list all the domains
listed in the xCAT network definitions and the xCAT site definiton.

The "nameservers" value can either be set to a specific IP address or the "<xcatmaster>" key word.  The "<xcatmaster>" key word means that the value of the "xcatmaster" attribute of the node definition will be used in the /etc/resolv.conf file.  (I.e.  The name of the install server as known by the node.)

You can set the "domain" and "nameservers" attributes by using the \ **chdef**\  command.  For example:


.. code-block:: perl

  chdef -t network -o clstr_net domain=cluster.com nameservers=<xcatmaster>


If the "domain" and "nameservers" attributes are not set in either the nodes "network" definition or the "site" definition then no new NIM resolv_conf resource
will be created.

You can specify additional attributes and values using the "attr=val" command line option.  This information will be passed on to the underlying call to the NIM "nim -o bos_inst" command.  See the NIM documentation for information on valid command line options for the nim command.  The "attr" must correspond to a NIM attribute supported for the NIM "bos_inst" operation.  Information provided by the "attr=val" option will take precedence over the information provided in the osimage definition.

The force option can be used to reinitialize a node if it already has resources allocated or it is in the wrong NIM state. This option will reset the NIM node and deallocate resources before reinititializing.

This command will also create a NIM script resource to enable the xCAT support for user-provided customization scripts.

After the \ **nimnodeset**\  command completes you can use the \ **lsnim**\  command to check the NIM node definition to see if it is ready for booting the node. ("lsnim -l <nim_node_name>").

You can supply your own scripts to be run on the management node  or on the service node (if their is hierarchy) for a node during the \ **nimnodeset**\  command. Such scripts are called \ **prescripts**\ . They should be copied to /install/prescripts dirctory. A table called \ *prescripts*\  is used to specify the scripts and their associated actions. The scripts to be run at the beginning of the \ **nimnodeset**\  command are stored in the 'begin' column of \ *prescripts*\  table. The scripts to be run at the end of the \ **nimnodeset**\  command are stored in the 'end' column of \ *prescripts*\  table. Please run 'tabdump prescripts -d' command for details. An example for the 'begin' or the 'end' column is: \ *standalone:myscript1,myscript2*\ . The following two environment variables will be passed to each script: NODES contains all the names of the nodes that need to run the script for and ACTION contains the current nodeset action, in this case "standalone". If \ *#xCAT setting:MAX_INSTANCE=number*\  is specified in the script, the script will get invoked for each node in parallel, but no more than \ *number*\  of instances will be invoked at at a time. If it is not specified, the script will be invoked once for all the nodes.


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=
 val pairs must be specified last on the command line. These are used to specify additional values that can be passed to the underlying NIM commands, ("nim -o bos_inst ...").  See the NIM documentation for valid "nim" command line options. Note that you may specify multiple "script" and "installp_bundle" values by using a comma seperated list. (ex. "script=ascript,bscript").
 


\ **-b|-**\ **-backupSN**\ 
 
 When using backup service nodes only update the backup.  The default is to update both the primary and backup service nodes
 


\ **-f |-**\ **-force**\ 
 
 Use the force option to reinitialize the NIM machines.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-i**\  \ *image_name*\ 
 
 The name of an existing xCAT osimage definition.
 


\ **-l|-**\ **-location**\ 
 
 The directory location to use when creating new NIM resolv_conf resources. The d
 efault location is /install/nim.
 


\ **-p|-**\ **-primarySN**\ 
 
 When using backup service nodes only update the primary.  The default is to update both the primary and backup service nodes.
 


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


1) Initialize an xCAT node named "node01".  Use the xCAT osimage named "61gold" to install the node.


.. code-block:: perl

  nimnodeset -i 61gold node01


2) Initialize all AIX nodes contained in the xCAT node group called "aixnodes" using the image definitions pointed to by the "provmethod" attribute of the xCAT node definitions.


.. code-block:: perl

  nimnodeset aixnodes


3) Initialize an xCAT node called "node02".  Include installp_bundle resources that are not included in the osimage definition. This assumes the NIM installp_bundle resources have already been created.


.. code-block:: perl

  nimnodeset -i 611image node02 installp_bundle=sshbundle,addswbundle



*****
FILES
*****


/opt/xcat/bin/nimnodeset


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mknimimage(1)|mknimimage.1, rnetboot(1)|rnetboot.1

