
############
rmosdistro.8
############

.. highlight:: perl


********
SYNOPSIS
********


\ **rmosdistro**\  [\ **-a | -**\ **-all**\ ] [\ **-f | -**\ **-force**\ ] \ *osdistroname*\  [\ *osdistroname2 ...*\ ]

\ **rmosdistro**\  [\ **-h | -**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **rmosdistro**\  command removes the specified OS Distro that was created by \ **copycds**\ . To delete all OS Distro entries, please specify \ **[-a|-**\ **-all]**\ . If the specified OS Distro is referenced by some osimage, \ **[-f|force]**\  can be used to remove it.


*********
ARGUMENTS
*********


The OS Distro names to delete, delimited by blank space.


*******
OPTIONS
*******



\ **-a | -**\ **-all**\ 
 
 If specified, try to delete all the OS Distros.
 


\ **-f | -**\ **-force**\ 
 
 Remove referenced OS Distros, never prompt.
 


\ **-h | -**\ **-help**\ 
 
 Show info of rmosdistro usage.
 



************
RETURN VALUE
************


Zero:                    
  The command completed successfully.

Nonzero:
  An Error has occurred.


********
EXAMPLES
********



1. To remove OS Distro "rhels6.2-ppc64" and "sles11.2-ppc64":
 
 
 .. code-block:: perl
 
   rmosdistro rhels6.2-ppc64 sles11.2-ppc64
 
 


2. To remove OS Distro "rhels6.2-ppc64", regardless of whether is referenced by any osimage:
 
 
 .. code-block:: perl
 
   rmosdistro -f rhels6.2-ppc64
 
 


3. To remove all OS Distros:
 
 
 .. code-block:: perl
 
   rmosdistro -a
 
 


