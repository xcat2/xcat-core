
########
monadd.1
########

.. highlight:: perl


****
NAME
****


\ **monadd**\  - Registers a monitoring plug-in to the xCAT cluster.


********
SYNOPSIS
********


\ **monadd  [-h| -**\ **-help]**\ 

\ **monadd  [-v| -**\ **-version]**\ 

\ **monadd  name [-n|-**\ **-nodestatmon] [-s|-**\ **-settings**\  \ *settings]*\ 


***********
DESCRIPTION
***********


This command is used to register a monitoring plug-in module to monitor the xCAT cluster. The plug-in module will be added to the xCAT \ *monitoring*\  database table and the configuration scripts for the monitoring plug-in, if any, will be added to the \ *postscripts*\  table. A monitoring plug-in module acts as a bridge that connects a 3rd party monitoring software and the xCAT cluster. A configuration script is used to configure the 3rd party software. Once added to the <postscripts> table, it will be invoked on the nodes during node deployment stage.


**********
Parameters
**********


\ *name*\  is the name of the monitoring plug-in module. For example, if the the \ *name*\  is called \ *xxx*\ , then the actual file name that the xcatd looks for is \ */opt/xcat/lib/perl/xCAT_monitoring/xxx.pm*\ . Use \ *monls -a*\  command to list all the monitoring plug-in modules that can be used.

\ *settings*\  is the monitoring plug-in specific settings. It is used to customize the behavior of the plug-in or configure the 3rd party software. Format: \ *-s key-value -s key=value ...*\  Note that the square brackets are needed here. Use \ *monls name -d*\  command to look for the possbile setting keys for a plug-in module.


*******
OPTIONS
*******



\ **-h | -**\ **-help**\ 
 
 Display usage message.
 


\ **-n | -**\ **-nodestatmon**\ 
 
 Indicate that this monitoring plug-in will be used for feeding the node liveness status to the xCAT \ *nodelist*\  table.
 


\ **-s | -**\ **-settings**\ 
 
 Specifies the plug-in specific settings. These settings will be used by the plug-in to customize certain entities for the plug-in or the third party monitoring software. e.g. -s mon_interval=10 -s toggle=1.
 


\ **-v | -**\ **-version**\ 
 
 Command Version.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To register gangliamon plug-in module (which interacts with Ganglia monitoring software) to monitor the xCAT cluster, enter:
 
 
 .. code-block:: perl
 
    monadd gangliamon
 
 


2.
 
 To register rmcmon plug-in module (which interacts with IBM's RSCT monitoring software) to monitor the xCAT cluster and have it feed the node liveness status to xCAT's \ *nodelist*\  table, enter:
 
 
 .. code-block:: perl
 
    monadd rmcmon -n
 
 
 This will also add the \ *configrmcnode*\  to the \ *postscripts*\  table. To view the content of the \ *postscripts*\  table, enter:
 
 
 .. code-block:: perl
 
    tabdump postscritps
    #node,postscripts,comments,disable
    "service","servicenode",,
    "xcatdefaults","syslog,remoteshell,configrmcnode",,
 
 


3.
 
 To register xcatmon plug-in module to feed the node liveness status to xCAT's \ *nodelist*\  table, enter:
 
 
 .. code-block:: perl
 
    monadd xcatmon -n -s ping-interval=2
 
 
 where 2 is the number of minutes between the pings.
 



*****
FILES
*****


/opt/xcat/bin/monadd


********
SEE ALSO
********


monls(1)|monls.1, monrm(1)|monrm.1, monstart(1)|monstart.1, monstop(1)|monstop.1, moncfg(1)|moncfg.1, mondecfg(1)|mondecfg.1

