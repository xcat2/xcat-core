
#########
monstop.1
#########

.. highlight:: perl


****
NAME
****


\ **monstop**\  -  Stops a monitoring plug-in module to monitor the xCAT cluster.


********
SYNOPSIS
********


\ **monstop [-h| -**\ **-help]**\ 

\ **monstop [-v| -**\ **-version]**\ 

\ **monstop**\  \ *name*\  [\ *noderange*\ ] [\ **-r|-**\ **-remote**\ ]


***********
DESCRIPTION
***********


This command is used to stop a 3rd party software, (for example stop the daemons), from monitoring the xCAT cluster. The operation is performed on the management node and the service nodes of the given nodes.  The operation will also be performed on the nodes if the \ **-r**\  option is specified.


**********
PARAMETERS
**********


\ *name*\  is the name of the monitoring plug-in module in the \ *monitoring*\  table. Use \ **monls**\  command to list all the monitoring plug-in modules that can be used.

\ *noderange*\  is the nodes to be stopped for monitoring. If omitted, all nodes will be stopped.


*******
OPTIONS
*******


\ **-h | -help**\           Display usage message.

\ **-r | -**\ **-remote**\        Specifies that the operation will also be performed on the nodes. For example, the3rd party monitoring software daemons on the nodes will also be stopped.

\ **-v | -version**\        Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1.To stop gangliamon plug-in module (which interacts with Ganglia monitoring software) to monitor the xCAT cluster, enter:


.. code-block:: perl

   monstop gangliamon


Note that gangliamon must have been registered in the xCAT \ *monitoring*\  table. For a list of registered plug-in modules, use command \ *monls*\ .


*****
FILES
*****


/opt/xcat/bin/monstop


********
SEE ALSO
********


monls(1)|monls.1, monstart(1)|monstart.1, monadd(1)|monadd.1, monrm(1)|monrm.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

