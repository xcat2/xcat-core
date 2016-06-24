
######
pasu.1
######

.. highlight:: perl


****
NAME
****


\ **pasu**\  - run the ASU to many nodes in parallel


********
SYNOPSIS
********


\ **pasu**\  [\ **-V**\ ] [\ **-d**\ ] [\ **-l**\  \ *user*\ ] [\ **-p**\  \ *passwd*\ ] [\ **-f**\  \ *fanout*\ ] [\ **-i**\  \ *hostname-suffix*\ ] \ *noderange*\  \ *command*\ 

\ **pasu**\  [\ **-V**\ ] [\ **-d**\ ] [\ **-l**\  \ *user*\ ] [\ **-p**\  \ *passwd*\ ] [\ **-f**\  \ *fanout*\ ] [\ **-i**\  \ *hostname-suffix*\ ] \ **-b**\  \ *batchfile*\  \ *noderange*\ 

\ **pasu**\  [\ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **pasu**\  command runs the ASU command in out-of-band mode in parallel to multiple nodes.  Out-of-band mode means
that ASU connects from the xCAT management node to the IMM (BMC) of each node to set or query the ASU settings.  To
see all of the ASU settings available on the node, use the "show all" command.  To query or set multiple values,
use the \ **-b**\  (batch) option.  To group similar output from multiple nodes, use xcoll(1)|xcoll.1.

Before running \ **pasu**\ , you must install the ASU RPM from IBM.  You can download it from the IBM Fix Central site.
You also must configure the IMMs properly according to xCAT documentation.  Run "\ **rpower**\  \ *noderange*\  \ **stat**\ "
to confirm that the IMMs are configured properly.


*******
OPTIONS
*******



\ **-l|-**\ **-loginname**\  \ *username*\ 
 
 The username to use to connect to the IMMs.  If not specified, the row in the xCAT \ **passwd**\  table with key "ipmi"
 will be used to get the username.
 


\ **-p|-**\ **-passwd**\  \ *passwd*\ 
 
 The password to use to connect to the IMMs.  If not specified, the row in the xCAT passwd table with key "ipmi"
 will be used to get the password.
 


\ **-f|-**\ **-fanout**\ 
 
 How many processes to run in parallel simultaneously.  The default is 64.  You can also set the XCATPSHFANOUT
 environment variable.
 


\ **-b|-**\ **-batch**\  -\ *batchfile*\ 
 
 A simple text file that contains multiple ASU commands, each on its own line.
 


\ **-d|-**\ **-donotfilter**\ 
 
 By default, pasu filters out (i.e. does not display) the standard initial output from ASU:
 
 
 .. code-block:: perl
 
   IBM Advanced Settings Utility version 9.30.79N
   Licensed Materials - Property of IBM
   (C) Copyright IBM Corp. 2007-2012 All Rights Reserved
   Connected to IMM at IP address node2-imm
 
 
 If you want this output to be displayed, use this flag.
 


\ **-i|-**\ **-interface**\  \ *hostname-suffix*\ 
 
 The hostname suffix to be appended to the node names.
 


\ **-V|-**\ **-verbose**\ 
 
 Display verbose messages.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 To display the Com1ActiveAfterBoot setting on 2 nodes:
 
 
 .. code-block:: perl
 
   pasu node1,node2 show DevicesandIOPorts.Com1ActiveAfterBoot
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     node1: DevicesandIOPorts.Com1ActiveAfterBoot=Enable
     node2: DevicesandIOPorts.Com1ActiveAfterBoot=Enable
 
 


2.
 
 To display the Com1ActiveAfterBoot setting on all compute nodes:
 
 
 .. code-block:: perl
 
   pasu compute show DevicesandIOPorts.Com1ActiveAfterBoot | xcoll
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     ====================================
     compute
     ====================================
     DevicesandIOPorts.Com1ActiveAfterBoot=Enable
 
 


3.
 
 To set several settings on all compute nodes, create a batch file
 called (for example) asu-settings with contents:
 
 
 .. code-block:: perl
 
   set DevicesandIOPorts.Com1ActiveAfterBoot Enable
   set DevicesandIOPorts.SerialPortSharing Enable
   set DevicesandIOPorts.SerialPortAccessMode Dedicated
   set DevicesandIOPorts.RemoteConsole Enable
 
 
 Then run:
 
 
 .. code-block:: perl
 
   pasu -b asu-settings compute | xcoll
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     ====================================
     compute
     ====================================
     Batch mode start.
     [set DevicesandIOPorts.Com1ActiveAfterBoot Enable]
     DevicesandIOPorts.Com1ActiveAfterBoot=Enable
  
     [set DevicesandIOPorts.SerialPortSharing Enable]
     DevicesandIOPorts.SerialPortSharing=Enable
  
     [set DevicesandIOPorts.SerialPortAccessMode Dedicated]
     DevicesandIOPorts.SerialPortAccessMode=Dedicated
  
     [set DevicesandIOPorts.RemoteConsole Enable]
     DevicesandIOPorts.RemoteConsole=Enable
  
     Beginning intermediate batch update.
     Waiting for command completion status.
     Command completed successfully.
     Completed intermediate batch update.
     Batch mode competed successfully.
 
 


4.
 
 To confirm that all the settings were made on all compute nodes, create a batch file
 called (for example) asu-show with contents:
 
 
 .. code-block:: perl
 
   show DevicesandIOPorts.Com1ActiveAfterBoot
   show DevicesandIOPorts.SerialPortSharing
   show DevicesandIOPorts.SerialPortAccessMode
   show DevicesandIOPorts.RemoteConsole
 
 
 Then run:
 
 
 .. code-block:: perl
 
   pasu -b asu-show compute | xcoll
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
     ====================================
     compute
     ====================================
     Batch mode start.
     [show DevicesandIOPorts.Com1ActiveAfterBoot]
     DevicesandIOPorts.Com1ActiveAfterBoot=Enable
  
     [show DevicesandIOPorts.SerialPortSharing]
     DevicesandIOPorts.SerialPortSharing=Enable
  
     [show DevicesandIOPorts.SerialPortAccessMode]
     DevicesandIOPorts.SerialPortAccessMode=Dedicated
  
     [show DevicesandIOPorts.RemoteConsole]
     DevicesandIOPorts.RemoteConsole=Enable
  
     Batch mode competed successfully.
 
 



*****
FILES
*****


/opt/xcat/bin/pasu


********
SEE ALSO
********


noderange(3)|noderange.3, rpower(1)|rpower.1, xcoll(1)|xcoll.1

