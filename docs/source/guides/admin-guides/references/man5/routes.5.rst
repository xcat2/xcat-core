
########
routes.5
########

.. highlight:: perl


****
NAME
****


\ **routes**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **routes Attributes:**\   \ *routename*\ , \ *net*\ , \ *mask*\ , \ *gateway*\ , \ *ifname*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Describes the additional routes needed to be setup in the os routing table. These routes usually are used to connect the management node to the compute node using the service node as gateway.


******************
routes Attributes:
******************



\ **routename**\ 
 
 Name used to identify this route.
 


\ **net**\ 
 
 The network address.
 


\ **mask**\ 
 
 The network mask.
 


\ **gateway**\ 
 
 The gateway that routes the ip traffic from the mn to the nodes. It is usually a service node.
 


\ **ifname**\ 
 
 The interface name that facing the gateway. It is optional for IPv4 routes, but it is required for IPv6 routes.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

