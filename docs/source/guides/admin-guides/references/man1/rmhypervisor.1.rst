
##############
rmhypervisor.1
##############

.. highlight:: perl


****
NAME
****


\ **rmhypervisor**\  - Remove the virtualization hosts.


********
SYNOPSIS
********


\ **RHEV specific :**\ 


\ **rmhypervisor**\  \ *noderange*\  [\ **-f**\ ]


***********
DESCRIPTION
***********


The \ **rmhypervisor**\  command can be used to remove the virtualization host.


*******
OPTIONS
*******



\ **-f**\ 
 
 If \ **-f**\  is specified, the host will be deactivated to maintenance before the removing.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To remove the host 'host1', enter:
 
 
 .. code-block:: perl
 
   rmhypervisor host1
 
 



*****
FILES
*****


/opt/xcat/bin/rmhypervisor

