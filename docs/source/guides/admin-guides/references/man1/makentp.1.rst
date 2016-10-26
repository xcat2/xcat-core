
#########
makentp.1
#########

.. highlight:: perl


********
SYNOPSIS
********


\ **makentp [-h|-**\ **-help]**\ 

\ **makentp [-v|-**\ **-version]**\ 

\ **makentp [-a|-**\ **-all] [-V|-**\ **-verbose]**\ 


***********
DESCRIPTION
***********


\ **makentp**\  command sets up the NTP server on the xCAT management node and the service node.

By default, it sets up the NTP server for xCAT management node. If -a flag is specified, the command will setup the ntp servers for management node as well as all the service nodes that have \ *servicenode.ntpserver*\  set. It honors the site table attributes \ *extntpservers*\  and \ *ntpservers*\  described below:


\ *site.extntpservers*\  -- the NTP servers for the management node to sync with. If it is empty then the NTP server will use the management node's own hardware clock to calculate the system date and time.

\ *site.ntpservers*\  -- the NTP servers for the service node and compute node to sync with. The keyword <xcatmaster> means that the node's NTP server is the node that is managing it (either its service node or the management node).

To setup NTP on the compute node, add \ **setupntp**\  postscript to the \ *postscripts*\  table and run \ *updatenode node -P setupntp*\  command.


*******
OPTIONS
*******



\ **-a|-**\ **-all**\ 
 
 Setup NTP servers for both management node and the service node.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1. To setup NTP server on the management node:
 
 
 .. code-block:: perl
 
   makentp
 
 


2. To setup NTP servers on both management node and the service node:
 
 
 .. code-block:: perl
 
   makentp -a
 
 



*****
FILES
*****


/opt/xcat/bin/makentp


********
SEE ALSO
********


