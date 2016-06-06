
#######
route.7
#######

.. highlight:: perl


****
NAME
****


\ **route**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **route Attributes:**\   \ *gateway*\ , \ *ifname*\ , \ *mask*\ , \ *net*\ , \ *routename*\ , \ *usercomment*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


*****************
route Attributes:
*****************



\ **gateway**\  (routes.gateway)
 
 The gateway that routes the ip traffic from the mn to the nodes. It is usually a service node.
 


\ **ifname**\  (routes.ifname)
 
 The interface name that facing the gateway. It is optional for IPv4 routes, but it is required for IPv6 routes.
 


\ **mask**\  (routes.mask)
 
 The network mask.
 


\ **net**\  (routes.net)
 
 The network address.
 


\ **routename**\  (routes.routename)
 
 Name used to identify this route.
 


\ **usercomment**\  (routes.comments)
 
 Any user-written notes.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

