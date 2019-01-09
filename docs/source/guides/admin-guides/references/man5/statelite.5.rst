
###########
statelite.5
###########

.. highlight:: perl


****
NAME
****


\ **statelite**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **statelite Attributes:**\   \ *node*\ , \ *image*\ , \ *statemnt*\ , \ *mntopts*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The location on an NFS server where a nodes persistent files are stored.  Any file marked persistent in the litefile table will be stored in the location specified in this table for that node.


*********************
statelite Attributes:
*********************



\ **node**\ 
 
 The name of the node or group that will use this location.
 


\ **image**\ 
 
 Reserved for future development, not used.
 


\ **statemnt**\ 
 
 The persistent read/write area where a node's persistent files will be written to, e.g: 10.0.0.1/state/.  The node name will be automatically added to the pathname, so 10.0.0.1:/state, will become 10.0.0.1:/state/<nodename>.
 


\ **mntopts**\ 
 
 A comma-separated list of options to use when mounting the persistent directory.  (Ex. 'soft') The default is to do a 'hard' mount.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

