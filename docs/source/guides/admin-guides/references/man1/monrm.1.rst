
#######
monrm.1
#######

.. highlight:: perl


****
NAME
****


\ **monrm**\  -  Unregisters a monitoring plug-in module from the xCAT cluster.


********
SYNOPSIS
********


\ **monrm [-h| -**\ **-help]**\ 

\ **monrm [-v| -**\ **-version]**\ 

\ **monrm**\  \ *name*\ 


***********
DESCRIPTION
***********


This command is used to unregister a monitoring plug-in module from the \ *monitoring*\  table. It also removes any configuration scripts associated with the monitoring plug-in from the \ *postscripts*\  table.  A monitoring plug-in module acts as a bridge that connects a 3rd party monitoring software and the xCAT cluster. A configuration script is used to configure the 3rd party software. Once added to the \ *postscripts*\  table, it will be invoked on the nodes during node deployment stage.


**********
PARAMETERS
**********


\ *name*\  is the name of the monitoring plug-in module in the \ *monitoring*\  table.  Use \ *monls*\  command to list all the monitoring plug-in modules that can be used.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\           Display usage message.

\ **-v | -**\ **-version**\        Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1.To unregister gangliamon plug-in module (which interacts with Ganglia monitoring software) from the xCAT cluster, enter:


.. code-block:: perl

   monrm gangliamon


Note that gangliamon must have been registered in the xCAT \ *monitoring*\  table. For a list of registered plug-in modules, use command \ **monls**\ .


*****
FILES
*****


/opt/xcat/bin/monrm


********
SEE ALSO
********


monls(1)|monls.1, monadd(1)|monadd.1, monstart(1)|monstart.1, monstop(1)|monstop.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

