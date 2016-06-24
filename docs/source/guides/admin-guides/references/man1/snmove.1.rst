
########
snmove.1
########

.. highlight:: perl


****
NAME
****


\ **snmove**\  - Move xCAT compute nodes to a different xCAT service node.


********
SYNOPSIS
********


\ **snmove**\  \ *noderange*\  [\ **-V**\ ] [\ **-l | -**\ **-liteonly**\ ] [\ **-d | -**\ **-dest**\  \ *sn2*\ ] [\ **-D | -**\ **-destn**\  \ *sn2n*\ ] [\ **-i | -**\ **-ignorenodes**\ ] [\ **-P | -**\ **-postscripts**\  \ *script1,script2...*\  | \ **all**\ ]

\ **snmove**\  [\ **-V**\ ] [\ **-l | -**\ **-liteonly**\ ] \ **-s | -**\ **-source**\  \ *sn1*\  [\ **-S | -**\ **-sourcen**\  \ *sn1n*\ ] [\ **-d | -**\ **-dest**\  \ *sn2*\ ] [\ **-D | -**\ **-destn**\  \ *sn2n*\ ] [\ **-i | -**\ **-ignorenodes**\ ] [\ **-P | -**\ **-postscripts**\  \ *script1,script2...*\  | \ **all**\ ]

\ **snmove**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **snmove**\  command may be used to move a node or nodes from one service node to another backup service node.

The use of backup service nodes in an xCAT hierarchical cluster can
help improve the overall reliability, availability, and serviceability
of the cluster.

Before you run the \ **snmove**\  command it is assumed that the backup
service node has been configured properly to manage the new node
or nodes. (See the xCAT document named
"Using xCAT Service Nodes with AIX" for information on how to set
up backup AIX service nodes.).

The \ **snmove**\  command can use the information stored in the xCAT
database or information passed in on the command line to determine
the current service node and the backup service node.

To specify the primary and backup service nodes you can set the
"servicenode" attribute of the node definitions.

The \ **servicenode**\  attribute is the hostname of the xCAT service node
as it is known by the management node. The \ **xcatmaster**\  attribute
is the hostname of the xCAT service node as known by the node.
The \ **servicenode**\  attribute should be set to a comma-separated list
so that the primary service node is first and the backup service
node is second.  The \ **xcatmaster**\  attribute must be set to the
hostname of the primary service node as it is known by the node.

When the \ **snmove**\  command is run it modifies the xCAT database to
switch the the primary server to the backup server.

It will also check the other services that are being used for the
node (tftpserver, monserver, nfsserver, conserver), and if they were set 
to the original service node they will be changed to point to the backup
service node.

By default the command will modify the nodes so that they will be able to be managed by the backup service node.

If the \ **-i**\  option is specified, the nodes themselves will not be modified.

You can also have postscripts executed on the nodes by using the -P option if needed.

The xCAT \ **snmove**\  command may also be used to synchronize statelite persistent files from the primary service node to the backup service node without actually moving the nodes to the backup servers.

If you run the command with the "-l" option it will attempt to use rsync to update the statelite persistent directory on the backup service node. This will only be done if the server specified in the "statelite" table is the primary service node.

When the \ **snmove**\  command is executed the new service node must be running but
the original service node may be down.

Note: On a Linux cluster, for NFS statelite nodes that do not use external NFS server, if the original service node is down, the nodes it manages will be down too. You must run nodeset command and then reboot the nodes after running snmove. For stateless nodes and RAMDisk statelite nodes, the nodes will be up even if the original service node is down. However, make sure to run nodeset command if you decide to reboot the nodes later.


*******
OPTIONS
*******



\ **-d|-**\ **-dest**\ 
 
 Specifies the hostname of the new destination service node as known by (facing) the management node.
 


\ **-D|-**\ **-destn**\ 
 
 Specifies the hostname of the destination service node as known by (facing) the nodes.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-i|-**\ **-ignorenodes**\ 
 
 No modifications will be made on the nodes. If not specified, several xCAT postscripts will be run on the nodes to complete the switch to the new service node.
 


\ **-l|-**\ **-liteonly**\ 
 
 Use this option to ONLY synchronize any AIX statelite files from the primary server to the backup server for the nodes. It will not do the actual moving of thre nodes the the backup servers.
 


\ **-P|-**\ **-postscripts**\ 
 
 Specifies a list of extra postscripts to be run on the nodes after the nodes are moved over to the new serive node. If \ **all**\  is specified, all the postscripts defined in the postscripts table will be run for the nodes. The specified postscripts must be stored under /install/postscripts directory.
 


\ **-s|-**\ **-source**\ 
 
 Specifies the hostname of the current (source) service node sa known by (facing) the management node.
 


\ **-S|-**\ **-sourcen**\ 
 
 Specifies the hostname of the current service node adapter as known by (facing)
 the nodes.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 



********
EXAMPLES
********



1.
 
 Move the nodes contained in group "group1" to the service node named "xcatsn02".
 
 
 .. code-block:: perl
 
   snmove group1 -d xcatsn02 -D xcatsn02-eth1
 
 


2.
 
 Move all the nodes that use service node xcatsn01 to service node xcatsn02.
 
 
 .. code-block:: perl
 
   snmove -s xcatsn01 -S xcatsn01-eth1 -d xcatsn02 -D xcatsn02-eth1
 
 


3.
 
 Move any nodes that have sn1 as their primary server to the backup service node set in the xCAT node definition.
 
 
 .. code-block:: perl
 
   snmove -s sn1
 
 


4.
 
 Move all the nodes in the xCAT group named "nodegroup1" to their backup SNs.
 
 
 .. code-block:: perl
 
   snmove nodegroup1
 
 


5.
 
 Move all the nodes in xCAT group "sngroup1" to the service node named "xcatsn2".
 
 
 .. code-block:: perl
 
   snmove sngroup1 -d xcatsn2
 
 


6.
 
 Move all the nodes in xCAT group "sngroup1" to the SN named "xcatsn2" and run extra postscripts.
 
 
 .. code-block:: perl
 
   snmove sngroup1 -d xcatsn2 -P test1
 
 


7.
 
 Move all the nodes in xCAT group "sngroup1" to the SN named "xcatsn2" and do not run anything on the nodes.
 
 
 .. code-block:: perl
 
   snmove sngroup1 -d xcatsn2 -i
 
 


8.
 
 Synchronize any AIX statelite files from the primary server for compute03 to the backup server.  This will not actually move the node to it's backup service node.
 
 
 .. code-block:: perl
 
   snmove compute03 -l -V
 
 



*****
FILES
*****


/opt/xcat/sbin/snmove


********
SEE ALSO
********


noderange(3)|noderange.3

