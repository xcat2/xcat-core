
##########
litetree.5
##########

.. highlight:: perl


****
NAME
****


\ **litetree**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **litetree Attributes:**\   \ *priority*\ , \ *image*\ , \ *directory*\ , \ *mntopts*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Directory hierarchy to traverse to get the initial contents of node files.  The files that are specified in the litefile table are searched for in the directories specified in this table.


********************
litetree Attributes:
********************



\ **priority**\ 
 
 This number controls what order the directories are searched.  Directories are searched from smallest priority number to largest.
 


\ **image**\ 
 
 The name of the image (as specified in the osimage table) that will use this directory. You can also specify an image group name that is listed in the osimage.groups attribute of some osimages. 'ALL' means use this row for all images.
 


\ **directory**\ 
 
 The location (hostname:path) of a directory that contains files specified in the litefile table.  Variables are allowed.  E.g: $noderes.nfsserver://xcatmasternode/install/$node/#CMD=uname-r#/
 


\ **mntopts**\ 
 
 A comma-separated list of options to use when mounting the litetree directory.  (Ex. 'soft') The default is to do a 'hard' mount.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

