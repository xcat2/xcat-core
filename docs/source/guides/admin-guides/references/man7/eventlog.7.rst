
##########
eventlog.7
##########

.. highlight:: perl


****
NAME
****


\ **eventlog**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **eventlog Attributes:**\   \ *application*\ , \ *comments*\ , \ *component*\ , \ *disable*\ , \ *eventtime*\ , \ *eventtype*\ , \ *id*\ , \ *message*\ , \ *monitor*\ , \ *monnode*\ , \ *node*\ , \ *rawdata*\ , \ *recid*\ , \ *severity*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


********************
eventlog Attributes:
********************



\ **application**\  (eventlog.application)
 
 The application that reports the event.
 


\ **comments**\  (eventlog.comments)
 
 Any user-provided notes.
 


\ **component**\  (eventlog.component)
 
 The component where the event occurred.
 


\ **disable**\  (eventlog.disable)
 
 Do not use.  tabprune will not work if set to yes or 1
 


\ **eventtime**\  (eventlog.eventtime)
 
 The timestamp for the event.
 


\ **eventtype**\  (eventlog.eventtype)
 
 The type of the event.
 


\ **id**\  (eventlog.id)
 
 The location or the resource name where the event occurred.
 


\ **message**\  (eventlog.message)
 
 The full description of the event.
 


\ **monitor**\  (eventlog.monitor)
 
 The name of the monitor that monitors this event.
 


\ **monnode**\  (eventlog.monnode)
 
 The node that monitors this event.
 


\ **node**\  (eventlog.node)
 
 The node where the event occurred.
 


\ **rawdata**\  (eventlog.rawdata)
 
 The data that associated with the event.
 


\ **recid**\  (eventlog.recid)
 
 The record id.
 


\ **severity**\  (eventlog.severity)
 
 The severity of the event. Valid values are: informational, warning, critical.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

