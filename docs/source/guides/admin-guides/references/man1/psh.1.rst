
#####
psh.1
#####

.. highlight:: perl


****
Name
****


psh - parallel remote shell


****************
\ **Synopsis**\ 
****************


\ **psh**\  [\ **-i**\  \ *interface*\ ] [\ **-f**\  \ *fanout*\ ] [\ **-l**\  \ *user*\ ] \ *noderange*\  \ *command*\ 

\ **psh**\  {\ **-h | -**\ **-help | -v | -**\ **-version**\ }


*******************
\ **Description**\ 
*******************


\ **psh**\  is a utility used to run a command across a list of nodes in parallel.

\ **ssh**\  must be set up to allow no prompting for \ **psh**\  to work.

Note:

This command does not run through xcatd like most xCAT commands do.
This means you must either run it on the management node, or have a network connection between
your machine and the nodes. It does not support hierarchy, use xdsh to run remote command from the
management node to the compute node via a service node.

\ **psh**\  arguments need to precede noderange, otherwise, you will get unexpected errors.


***************
\ **Options**\ 
***************



\ **-i**\  \ *interface*\ 
 
 The NIC on the node that psh should communicate with.  For example, if \ *interface*\  is \ **eth1**\ ,
 then psh will concatenate \ **-eth1**\  to the end of every node name before ssh'ing to it.  This
 assumes those host names have been set up to resolve to the IP address of each of the eth1 NICs.
 


\ **-f**\  \ *fanout*\ 
 
 Specifies a fanout value for the maximum number of  concur-
 rently  executing  remote shell processes.
 


\ **-l**\  \ *user*\ 
 
 Log into the nodes as the specified username.  The default is to use the same username as you
 are running the psh command as.
 


\ **-n|-**\ **-nonodecheck**\ 
 
 Do not send the noderange to xcatd to expand it into a list of nodes.  Instead, use the noderange exactly as it is specified.
 In this case, the noderange must be a simple list of comma-separated hostnames of the nodes.
 This allows you to run \ **psh**\  even when xcatd is not running.
 


\ *noderange*\ 
 
 See noderange(3)|noderange.3.
 


\ *command*\ 
 
 Command  to  be run in parallel.  If no command is give then \ **psh**\ 
 enters interactive mode.  In interactive mode a  ">"  prompt  is
 displayed.   Any  command entered is executed in parallel to the
 nodes in the noderange. Use "exit" or "Ctrl-D" to end the interactive session.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 



*************************************
\ **Environment**\  \ **Variables**\ 
*************************************



\ **XCATPSHFANOUT**\ 
 
 Specifies  the fanout value. This variable is overridden by
 the \ **-f**\  flag.  Default is 64.
 



****************
\ **Examples**\ 
****************



1. Run uptime on 3 nodes:
 
 
 .. code-block:: perl
 
   psh node4-node6 uptime
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node4: Sun Aug  5 17:42:06 MDT 2001
   node5: Sun Aug  5 17:42:06 MDT 2001
   node6: Sun Aug  5 17:42:06 MDT 2001
 
 


2. Run a command on some BladeCenter management modules:
 
 
 .. code-block:: perl
 
   psh amm1-amm5 'info -T mm[1]'
 
 


3. Remove the tmp files on the nodes in the 1st frame:
 
 
 .. code-block:: perl
 
   psh rack01 'rm -f /tmp/*'
 
 
 Notice the use of '' to forward shell expansion.  This is not necessary
 in interactive mode.
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, pscp(1)|pscp.1, pping(1)|pping.1, prsync(1)|prsync.1

