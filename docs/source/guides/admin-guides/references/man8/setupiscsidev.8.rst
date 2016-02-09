
###############
setupiscsidev.8
###############

.. highlight:: perl


****
NAME
****


\ **setupiscsidev**\  - creates a LUN for a node to boot up with, using iSCSI


********
SYNOPSIS
********


\ **setupiscsidev**\  [\ **-s|-**\ **-size**\ ] \ *noderange*\ 

\ **setupiscsidev**\  [\ **-h|-**\ **-help|-v|-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **setupiscsidev**\  command will create a LUN on the management node (or service node) for each node
specified.  The LUN device can then be used by the node as an iSCSI device so the node can boot diskless,
stateful.


*******
OPTIONS
*******



\ **-s|-**\ **-size**\ 
 
 The size of the LUN that should be created.  Default is 4096.
 


\ **-v|-**\ **-version**\ 
 
 Display version.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
SEE ALSO
********


nodeset(8)|nodeset.8

