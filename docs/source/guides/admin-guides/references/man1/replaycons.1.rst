
############
replaycons.1
############

.. highlight:: perl


****
NAME
****


\ **replaycons**\  - replay the console output for a node


********
SYNOPSIS
********


\ **replaycons**\  [\ *node*\ ] [\ *bps*\ ] [\ *tail_amount*\ ]

\ **replaycons**\  [\ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **replaycons**\  command reads the console log stored by conserver for this node, and displays it
in a way that simulates the original output of the console.  Using the \ *bps*\  value, it will throttle
the speed of the output play back.  (The conserver logs are stored in /var/log/consoles.)

For now, replaycons must be run locally on the system on which the console log is stored.  This is normally
that management node, but in a hierarchical cluster will usually be the service node.


*******
OPTIONS
*******



\ *bps*\ 
 
 The display rate to use to play back the console output.  Default is 19200.
 


\ *tail_amount*\ 
 
 The place in the console log file to start play back, specified as the # of lines from the end.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1.
 
 To replay the console for node1 at the default rate, starting 2000 lines from the end:
 
 
 .. code-block:: perl
 
   replaycons 19200 2000
 
 



*****
FILES
*****


/opt/xcat/bin/replaycons


********
SEE ALSO
********


rcons(1)|rcons.1

