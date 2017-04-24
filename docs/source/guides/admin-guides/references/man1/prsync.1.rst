
########
prsync.1
########

.. highlight:: perl


****
Name
****


prsync - parallel rsync


****************
\ **Synopsis**\ 
****************


\ **prsync**\  \ *filename*\  [\ *filename*\  \ *...*\ ] \ *noderange:destinationdirectory*\ 

\ **prsync**\   [\ **-o**\  \ *rsyncopts*\ ] [\ **-f**\  \ *fanout*\ ] [\ *filename*\  \ *filename*\  \ *...*\ ] [\ *directory*\  \ *directory*\  \ *...*\ ]
\ *noderange:destinationdirectory*\ 

\ **prsync**\  {\ **-h | -**\ **-help | -v | -**\ **-version**\ }


*******************
\ **Description**\ 
*******************


\ **prsync**\  is a front-end to rsync for a single or range of nodes and/or groups in parallel.

Note:  this command does not support the xcatd client/server communication and therefore must be run on the management node. It does not support hierarchy, use \ **xdcp -F**\  to run rsync from the management node to the compute node via a service node

\ **prsync**\  is NOT multicast, but is parallel unicasts.


***************
\ **Options**\ 
***************



\ **-o**\  \ *rsyncopts*\ 
 
 rsync options.  See \ **rsync(1)**\ .
 


\ **-f**\  \ *fanout*\ 
 
 Specifies a fanout value for the maximum number of concurrently executing remote shell processes.
 


\ *filename*\ 
 
 A space delimited list of files to rsync.
 


\ *directory*\ 
 
 A space delimited list of directories to rsync.
 


\ *noderange:destination*\ 
 
 A noderange(3)|noderange.3 and destination directory.  The : is required.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



\ **XCATPSHFANOUT**\ 
 
 Specifies  the fanout value. This variable is overridden by
 the \ **-f**\  flag.  Default is 64.
 



****************
\ **Examples**\ 
****************



1.
 
 
 .. code-block:: perl
 
   cd /install; prsync -o "crz" post stage:/install
 
 


2.
 
 
 .. code-block:: perl
 
   prsync passwd group rack01:/etc
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, pscp(1)|pscp.1, pping(1)|pping.1, psh(1)|psh.1

