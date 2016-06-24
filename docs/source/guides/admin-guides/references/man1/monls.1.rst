
#######
monls.1
#######

.. highlight:: perl


****
NAME
****


\ **monls**\  - Lists monitoring plug-in modules that can be used to monitor the xCAT cluster.


********
SYNOPSIS
********


\ **monls [-h| -**\ **-help]**\ 

\ **monls  [-v| -**\ **-version]**\ 

\ **monls**\  \ *name*\  \ **[-d|-**\ **-description]**\ 

\ **monls [-a|-**\ **-all] [-d|-**\ **-description]**\ 


***********
DESCRIPTION
***********


This command is used to list the status, desctiption, the configuration scripts and the settings of one or all of the monitoring plug-in modules.


**********
Parameters
**********


\ *name*\  is the name of the monitoring plug-in module.


*******
OPTIONS
*******


\ **-a | -**\ **-all**\           Searches the \ *XCATROOT/lib/perl/xCAT_monitoring*\  directory and reports all the monitoring plug-in modules. If nothing is specified, the list is read from the \ *monitoring*\  tabel.

\ **-d | -**\ **-description**\   Display the description of the plug-in modules. The description ususally contains the possible settings.

\ **-h | -**\ **-help**\          Display usage message.

\ **-v | -**\ **-version**\       Command Version.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To list the status of all the monitoring plug-in modules from the \ *monitoring*\  table, enter:


.. code-block:: perl

   monls


The output looks like this:


.. code-block:: perl

   xcatmon         monitored       node-status-monitored
   snmpmon         not-monitored


2. To list the status of all the monitoring plug-in modules including the ones that are not in the monitoring table, enter


.. code-block:: perl

   monls -a


The output looks like this:


.. code-block:: perl

   xcatmon         monitored       node-status-monitored
   snmpmon         not-monitored
   gangliamon      not-monitored
   rmcmon          monitored
   nagiosmon       not-monitored


3. To list the status and the desciption for \ *snmpmon*\  module, enter:


.. code-block:: perl

   monls snmpmon -d



*****
FILES
*****


/opt/xcat/bin/monls


********
SEE ALSO
********


monadd(1)|monadd.1, monrm(1)|monrm.1, monstart(1)|monstart.1, monstop(1)|monstop.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

