
##########
mondecfg.1
##########

.. highlight:: perl


****
NAME
****


\ **mondecfg**\  - Deconfigures a 3rd party monitoring software from monitoring the xCAT cluster.


********
SYNOPSIS
********


\ **mondecfg [-h| -**\ **-help]**\ 

\ **mondecfg [-v| -**\ **-version]**\ 

\ **mondecfg**\  \ *name*\  \ *[noderange]*\  \ **[-r|-**\ **-remote]**\ 


***********
DESCRIPTION
***********


This command is used to deconfigure a 3rd party monitoring software from monitoring the xCAT cluster. The operation is performed on the management node and the service nodes of the given nodes. The operation will also be performed on the nodes if the \ *-r*\  option is specified. The deconfigration operation will remove the nodes from the 3rd party software's monitoring domain.


**********
PARAMETERS
**********


\ *name*\  is the name of the monitoring plug-in module.  Use \ *monls*\  command to list all the monitoring plug-in modules that can be used.

\ *noderange*\  specified the nodes to be deconfigured. If omitted, all nodes will be deconfigured.


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


1. To deconfigure the management node and the service nodes from the ganglia monitoring, enter:


.. code-block:: perl

   mondecfg gangliamon


2. To deconfigure the management node, nodes and their service nodes from the ganglia monitoring, enter:


.. code-block:: perl

   mondecfg gangliamon -r



*****
FILES
*****


/opt/xcat/bin/mondecfg


********
SEE ALSO
********


monls(1)|monls.1, moncfg(1)|moncfg.1, monadd(1)|monadd.1, monrm(1)|monrm.1, monstart(1)|monstart.1, monstop(1)|monstop.1

