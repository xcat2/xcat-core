
##############
xcatperftest.1
##############

.. highlight:: perl


****
NAME
****


\ **xcatperftest**\  - Run xCAT command performance baseline testing on fake nodes.


********
SYNOPSIS
********


\ **xcatperftest**\  [\ **-?|-h**\ ]

[\ **PERF_DRYRUN**\ =y] \ **xcatperftest run**\  [\ *command-list-file*\ ]

[\ **PERF_DRYRUN**\ =y] [\ **PERF_NOCREATE**\ =y] \ **xcatperftest**\  <total> [\ *command-list-file*\ ]


***********
DESCRIPTION
***********


The \ **xcatperftest**\  command runs commands defined in a command list file and get their execution response time baseline for performance purpose.
The \ **xcatperftest**\  command is part of the xCAT package \ **xCAT-test**\ , and you can run it standalone or leverage it to build up your automation test cases.

Any command could be defined in the command list file, however, it is recommended that the one-time initial configuration is well prepared prior to running \ **xcatperftest**\  command.
For example, the network object, osdistro and osimage image objects.

Follow the steps below to run \ **xcatperftest**\  command:

1. Install \ **xCAT-test**\  on a xCAT management node.

2. Prepare a command list with the commands you want to measure.

3. Prepare the initial configuration based on the command list to make sure all commands could be executed in techinal.

4. Run \ **xcatperftest**\  with the total fake nodes number and the above command list file.

Node: It is suggested to run the command in background as it normally takes long time to finish all the performance testing with large amount of fake nodes.


*******
OPTIONS
*******



\ **-?|-h**\ 
 
 Display usage message.
 


\ *command-list-file*\ 
 
 Specifies the command list file with full-path. xCAT supports an example command file: /opt/xcat/share/xcat/tools/autotest/perfcmds.lst
 


<total>
 
 Total number of fake nodes will be defined during the testing.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


*****************
COMMAND LIST FILE
*****************


The command list file is in flat text format, the testing framework will parse the file line by line, here is an example of the command list file:


.. code-block:: perl

   #SERIES# 1,50,100,250,500,1000,2500,5000
   mkdef -z -f < #STANZ#
   lsdef #NODES#
   makehosts #NODES#
   makedns -n #NODES#
   makedhcp #NODES#
   makeknownhosts #NODES#
   nodech #NODES# groups,=group1
   nodels #NODES# noderes
   nodeset #NODES# osimage=rhels7.3-GA-ppc64le-install-compute
   chdef -t node -o #NODES# postscripts="fake" profile="install" netboot="grub2"
   rmdef -t node #PERFGRP#
   mkdef -z < #STANZ#
   noderm #PERFGRP#


\ **Note**\ : Each line defines one command, and the commands dependency should be handled by the line order.
If you define a node range series line (started with \ **#SERIES#**\ ) in this file, xcatperftest will run the command for each node range defined in series line.

\ **#SERIES#**\        To define a node range series, and the series should be an comma split incremental number sequence.

\ **#STANZ#**\         It will be replaced with real stanz file path when this command line runs.

\ **#NODES#**\         It will be replaced with real node range defined in \ **#SERIES#**\  line when this command line runs. If no series line, the node group will be used.

\ **#PERFGRP#**\     It will be replaced with node group when this command line runs.


********************
ENVIRONMENT VARIABLE
********************


The \ **xcatperftest**\  command supports customization by some environment variables.

\ **FAKE_NODE_PREFIX**\ 

Optional, the prefix of the fake compute node name. By default, the value is 'fake'

\ **FAKE_NODE_GROUP**\ 

# Optional, the group name of all the fake compute nodes. By default, the value is 'perftest'

\ **FAKE_NETWORK_PRO**\ 

Mandatory, the Provision network for all the fake compute nodes. By default, the value is '192.168'.
It must be a string like 'A.B', and be matched with \`tabdump networks\`

\ **FAKE_NETWORK_BMC**\ 

Mandatory, the BMC network for all the fake compute nodes. By default, the value is '192.168'. Note:  It could not be the same subnet as 'FAKE_NETWORK_PRO'
It must be a string like 'A.B' and no need to be defined in 'networks' table.

\ **PERF_NODETEMPL**\ 

Optional, the node template name used for generating fake nodes. By default, it will be auto-detected according to the current arch.

\ **PERF_DRYRUN**\ 

Optional, indicate no real commands will be executed if the environment variable is set.

\ **PERF_NOCREATE**\ 

Optional, indicate no new fake nodes will be created if the environment variable is set.


********
EXAMPLES
********



1.
 
 To run the performance testing for the commands defined in /tmp/cmd.lst on 5000 fake nodes:
 
 
 .. code-block:: perl
 
    xcatperftest 5000 /tmp/cmd.lst
 
 


2.
 
 To generate an xCAT node object stanz file for 10000 nodes in subnet 10.100.0.0:
 
 
 .. code-block:: perl
 
    FAKE_NETWORK_PRO=10.100 FAKE_NETWORK_BMC=10.200 xcatperftest 10000
 
 


3.
 
 To run the performance testing for the commands defined in /opt/xcat/share/xcat/tools/autotest/perfcmds.lst on 5000 existing fake nodes:
 
 
 .. code-block:: perl
 
    PERF_NOCREATE=y xcatperftest 5000 /opt/xcat/share/xcat/tools/autotest/perfcmds.lst
 
 


4.
 
 To run the performance testing for the commands defined in /tmp/cmd.lst in existing xCAT environment:
 
 
 .. code-block:: perl
 
    xcatperftest run /tmp/cmd.lst
 
 



*****
FILES
*****


/opt/xcat/bin/xcatperftest

/opt/xcat/share/xcat/tools/autotest/perfcmds.lst

