
######
pscp.1
######

.. highlight:: perl


****
Name
****


\ **pscp**\  - parallel remote copy


****************
\ **Synopsis**\ 
****************


\ **pscp**\  [\ **-i**\  \ *suffix*\ ] [\ *scp options*\  \ *...*\ ] [\ **-f**\  \ *fanout*\ ] \ *filename*\  [\ *filename*\  \ *...*\ ] \ *noderange:destinationdirectory*\ 

\ **pscp**\  {\ **-h | -**\ **-help | -v | -**\ **-version**\ }


*******************
\ **Description**\ 
*******************


\ **pscp**\  is a utility used to copy a single or multiple set of files and/or
directories  to  a  single or range of nodes and/or groups in parallel.

\ **pscp**\  is a front-end to the remote copy \ **scp**\ .

Note:  this command does not support the xcatd client/server communication and therefore must be run on the management node. It does not support hierarchy, use xdcp to run remote copy command from the
management node to the compute node via a service node.

\ **pscp**\  is NOT multicast, but is parallel unicasts.


***************
\ **Options**\ 
***************



\ **-f**\  \ *fanout*\ 
 
 Specifies a fanout value for the maximum number of  concur-
 rently  executing  remote shell processes.
 


\ **-i**\  \ *suffix*\ 
 
 Interfaces to be used.
 


\ *scp options*\ 
 
 See \ **scp(1)**\ 
 


\ *filename*\ 
 
 A space delimited list of files to copy. If \ **-r**\  is passed as an scp option, directories may be specified as well.
 


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
 
   pscp -r /usr/local node1,node3:/usr/local
 
 


2.
 
 
 .. code-block:: perl
 
   pscp passwd group rack01:/etc
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, pping(1)|pping.1, prsync(1)|prsync.1, psh(1)|psh.1

