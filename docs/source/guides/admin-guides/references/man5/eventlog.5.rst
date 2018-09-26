
##########
eventlog.5
##########

.. highlight:: perl


****
NAME
****


\ **eventlog**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **eventlog Attributes:**\   \ *recid*\ , \ *eventtime*\ , \ *eventtype*\ , \ *monitor*\ , \ *monnode*\ , \ *node*\ , \ *application*\ , \ *component*\ , \ *id*\ , \ *severity*\ , \ *message*\ , \ *rawdata*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Stores the events occurred.


********************
eventlog Attributes:
********************



\ **recid**\ 
 
 The record id.
 


\ **eventtime**\ 
 
 The timestamp for the event.
 


\ **eventtype**\ 
 
 The type of the event.
 


\ **monitor**\ 
 
 The name of the monitor that monitors this event.
 


\ **monnode**\ 
 
 The node that monitors this event.
 


\ **node**\ 
 
 The node where the event occurred.
 


\ **application**\ 
 
 The application that reports the event.
 


\ **component**\ 
 
 The component where the event occurred.
 


\ **id**\ 
 
 The location or the resource name where the event occurred.
 


\ **severity**\ 
 
 The severity of the event. Valid values are: informational, warning, critical.
 


\ **message**\ 
 
 The full description of the event.
 


\ **rawdata**\ 
 
 The data that associated with the event.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Do not use.  tabprune will not work if set to yes or 1
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

