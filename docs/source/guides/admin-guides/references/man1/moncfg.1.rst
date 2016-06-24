
########
moncfg.1
########

.. highlight:: perl


****
NAME
****


\ **moncfg**\  - Configures a 3rd party monitoring software to monitor the xCAT cluster.


********
SYNOPSIS
********


\ **moncfg [-h| -**\ **-help]**\ 

\ **moncfg [-v| -**\ **-version]**\ 

\ **moncfg**\  \ *name*\  \ *[noderange]*\  \ **[-r|-**\ **-remote]**\ 


***********
DESCRIPTION
***********


This command is used to configure a 3rd party monitoring software to monitor the xCAT cluster. For example, it modifies the configration file for the monitoring software so that the nodes can be included in the monitoring domain. The operation is performed on the management node and the service nodes of the given nodes. The operation will also be performed on the nodes if the \ *-r*\  option is specified, though the configuration of the nodes is usually performed during the node deployment stage.


**********
Parameters
**********


\ *name*\  is the name of the monitoring plug-in module. For example, if the the \ *name*\  is called \ *xxx*\ , then the actual file name that the xcatd looks for is \ */opt/xcat/lib/perl/xCAT_monitoring/xxx.pm*\ . Use \ *monls -a*\  command to list all the monitoring plug-in modules that can be used.

\ *noderange*\  specifies the nodes to be monitored. If omitted, all nodes will be monitored.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\           Display usage message.

\ **-r | -**\ **-remote**\         Specifies that the operation will also be performed on the nodes.

\ **-v | -**\ **-version**\        Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To configure the management node and the service nodes for ganglia monitoring, enter:


.. code-block:: perl

   moncfg gangliamon


2. To configure the management node, nodes and their service nodes for ganglia monitoring, enter:


.. code-block:: perl

   moncfg gangliamon -r



*****
FILES
*****


/opt/xcat/bin/moncfg


********
SEE ALSO
********


monls(1)|monls.1, mondecfg(1)|mondecfg.1, monadd(1)|monadd.1, monrm(1)|monrm.1, monstart(1)|monstart.1, monstop(1)|monstop.1

