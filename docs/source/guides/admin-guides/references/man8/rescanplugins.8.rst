
###############
rescanplugins.8
###############

.. highlight:: perl


****
NAME
****


\ **rescanplugins**\  - Notifies xcatd to rescan the plugin directory


********
SYNOPSIS
********


\ **rescanplugins**\ 

\ **rescanplugins**\  [\ **-h | -**\ **-help**\ ]

\ **rescanplugins**\  [\ **-v | -**\ **-version**\ ]

\ **rescanplugins**\  [\ **-s | -**\ **-servicenodes**\ ]


***********
DESCRIPTION
***********


\ **rescanplugins**\  notifies the xcatd daemon to rescan the plugin directory and update its internal command handlers hash.  This command should be used when plugins have been added or removed from the xCAT plugin directory (/opt/xcat/lib/perl/xCAT_plugin) or if the contents of the handled_commands subroutine in an existing plugin has changed.

If rescanplugins is called as a subrequest from another command, the xcatd command handlers hash changes will not be available to that command's process.  Only subsequent command calls will see the updates.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Displays the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Displays the release version of the code.
 


\ **-s|-**\ **-servicenodes**\ 
 
 Process the rescanplugins on the management node and on all service nodes.  The rescanplugins command will be sent to the xcatd daemon on all nodes defined in the servicenode table.  The default is to only run on the management node.
 



********
EXAMPLES
********



1. To rescan the plugins only on the xCAT Management Node:
 
 
 .. code-block:: perl
 
   rescanplugins
 
 


2. To rescan the plugins on the xCAT Management Node and on all service nodes:
 
 
 .. code-block:: perl
 
   rescanplugins -s
 
 


