
#####
mic.5
#####

.. highlight:: perl


****
NAME
****


\ **mic**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **mic Attributes:**\   \ *node*\ , \ *host*\ , \ *id*\ , \ *nodetype*\ , \ *bridge*\ , \ *onboot*\ , \ *vlog*\ , \ *powermgt*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The host, slot id and configuration of the mic (Many Integrated Core).


***************
mic Attributes:
***************



\ **node**\ 
 
 The node name or group name.
 


\ **host**\ 
 
 The host node which the mic card installed on.
 


\ **id**\ 
 
 The device id of the mic node.
 


\ **nodetype**\ 
 
 The hardware type of the mic node. Generally, it is mic.
 


\ **bridge**\ 
 
 The virtual bridge on the host node which the mic connected to.
 


\ **onboot**\ 
 
 Set mic to autoboot when mpss start. Valid values: yes|no. Default is yes.
 


\ **vlog**\ 
 
 Set the Verbose Log to console. Valid values: yes|no. Default is no.
 


\ **powermgt**\ 
 
 Set the Power Management for mic node. This attribute is used to set the power management state that mic may get into when it is idle. Four states can be set: cpufreq, corec6, pc3 and pc6. The valid value for powermgt attribute should be [cpufreq=<on|off>]![corec6=<on|off>]![pc3=<on|off>]![pc6=<on|off>]. e.g. cpufreq=on!corec6=off!pc3=on!pc6=off. Refer to the doc of mic to get more information for power management.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Do not use.  tabprune will not work if set to yes or 1
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

