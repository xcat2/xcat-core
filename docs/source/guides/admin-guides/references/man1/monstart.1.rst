
##########
monstart.1
##########

.. highlight:: perl


****
NAME
****


\ **monstart**\  - Starts a plug-in module to monitor the xCAT cluster.


********
SYNOPSIS
********


\ **monstart [-h| -**\ **-help]**\ 

\ **monstart [-v| -**\ **-version]**\ 

\ **monstart**\  \ *name*\  \ *[noderange]*\  [\ **-r|-**\ **-remote**\ ]


***********
DESCRIPTION
***********


This command is used to start a 3rd party software, (for example start the daemons), to monitor the xCAT cluster. The operation is performed on the management node and the service nodes of the given nodes.  The operation will also be performed on the nodes if the \ **-r**\  option is specified.


**********
PARAMETERS
**********


\ *name*\  is the name of the monitoring plug-in module. For example, if the the \ *name*\  is called \ *xxx*\ , then the actual file name that the xcatd looks for is \ */opt/xcat/lib/perl/xCAT_monitoring/xxx.pm*\ . Use \ **monls -a**\  command to list all the monitoring plug-in modules that can be used.

\ *noderange*\  is the nodes to be monitored. If omitted, all nodes will be monitored.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\           Display usage message.

\ **-r | -**\ **-remote**\         Specifies that the operation will also be performed on the nodes. For example, the3rd party monitoring software daemons on the nodes will also be started.

\ **-v | -**\ **-version**\        Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To start gangliamon plug-in module (which interacts with Ganglia monitoring software) to monitor the xCAT cluster, enter:


.. code-block:: perl

   monstart gangliamon -r


2. To start xcatmon plug-in module to feed the node liveness status to xCAT's \ *nodelist*\  table, enter:


.. code-block:: perl

   monstart rmcmon



*****
FILES
*****


/opt/xcat/bin/monstart


********
SEE ALSO
********


monls(1)|monls.1, monstop(1)|monstop.1, monadd(1)|monadd.1, monrm(1)|monrm.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

