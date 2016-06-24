
##########
makedhcp.8
##########

.. highlight:: perl


****
NAME
****


\ **makedhcp**\  - Creates and updates DHCP configuration files.


********
SYNOPSIS
********


\ **makedhcp**\  \ **-n**\  [\ **-l | -**\ **-localonly**\ ]

\ **makedhcp**\  \ **-a**\  [\ **-l | -**\ **-localonly**\ ]

\ **makedhcp**\  \ **-a -d**\  [\ **-l | -**\ **-localonly**\ ]

\ **makedhcp**\  \ **-d**\  \ *noderange*\  [\ **-l | -**\ **-localonly**\ ]

\ **makedhcp**\  \ *noderange*\  [\ **-s**\  \ *statements*\ ] [\ **-l | -**\ **-localonly**\ ]

\ **makedhcp**\  \ **-q**\  \ *noderange*\ 

\ **makedhcp**\  \ **[-h|-**\ **-help]**\ 


***********
DESCRIPTION
***********


The \ **makedhcp**\  command creates and updates the DHCP configuration on the management node and service nodes. 
The \ **makedhcp**\  command is supported for both Linux and AIX clusters.


1.
 
 Start by filling out the networks(5)|networks.5 table properly.
 


2.
 
 Then use the \ **makedhcp -n**\  option to create a new dhcp configuration file.
 You can set the site table, dhcplease attribute to the lease time for the dhcp client. The default value is 43200.
 


3.
 
 Next, get the node IP addresses and MACs defined in the xCAT database.
 Also, get the hostnames and IP addresses pushed to /etc/hosts (using makehosts(8)|makehosts.8) and to DNS (using makedns(8)|makedns.8).
 


4.
 
 Then run \ **makedhcp**\  with a noderange or the \ **-a**\  option.  This will inject into dhcpd configuration data pertinent to the specified nodes.
 On linux, the configuration information immediately takes effect without a restart of DHCP.
 


If you need to delete node entries from the DHCP configuration, use the \ **-d**\  flag.


*******
OPTIONS
*******



\ **-n**\ 
 
 Create a new dhcp configuration file with a network statement for each network the dhcp daemon should listen on.
 (Which networks dhcpd should listen on can be controlled by the dhcpinterfaces attribute in the site(5)|site.5 table.)
 The \ **makedhcp**\  command will automatically restart the dhcp daemon after this operation.
 This option will replace any existing configuration file (making a backup of it first).
 For Linux systems the file will include network entries as well as certain general parameters such as a dynamic range and omapi configuration.
 For AIX systems the file will include network entries.
 On AIX systems, if there are any non-xCAT entries in the existing configuration file they will be preserved and added to the end of the new configuration file.
 


\ **-a**\ 
 
 Define all nodes to the DHCP server.  (Will only add nodes that can be reached, network-wise, by this DHCP server.)
 The dhcp daemon does not have to be restarted after this.
 On AIX systems \ **makedhcp**\  will not add entries for cluster nodes that will be installed using NIM.  The entries for these nodes will be managed by NIM.
 


\ *noderange*\ 
 
 Add the specified nodes to the DHCP server configuration.
 


\ **-s**\  \ *statements*\ 
 
 For the input noderange, the argument will be interpreted like dhcp configuration file text.
 


\ **-d**\  \ *noderange*\ 
 
 Delete node entries from the DHCP server configuration. On AIX, any entries created by NIM will not be removed.
 


\ **-a -d**\ 
 
 Delete all node entries, that were added by xCAT, from the DHCP server configuration.
 


\ **-l | -**\ **-localonly**\ 
 
 Configure dhcpd on the local machine only.  Without this option, makedhcp will also send this
 operation to any service nodes that service the nodes in the noderange.
 


\ **-q**\  \ *noderange*\ 
 
 Query the node entries from the DHCP server configuration. On AIX, any entries created by NIM will not be listed.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0. The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. Create a new DHCP configuration file and add the network definitions:
 
 
 .. code-block:: perl
 
   makedhcp -n
 
 


2. Define all nodes to the dhcp server:
 
 
 .. code-block:: perl
 
   makedhcp -a
 
 
 Note:  This does not add nodes that will be installed with AIX/NIM.
 


3. Will cause dhcp on the next request to set root-path appropriately for only node5.  Note some characters (e.g. ") must be doubly escaped (once for the shell, and once for the OMAPI layer).
 
 
 .. code-block:: perl
 
   makedhcp node5 -s 'option root-path  \"172.16.0.1:/install/freebsd6.2/x86_64\";'
 
 


4. Query a node from the DHCP server.
 
 
 .. code-block:: perl
 
   # makedhcp -q node01 
   node01: ip-address = 91.214.34.156, hardware-address = 00:00:c9:c6:6c:42
 
 



*****
FILES
*****


DHCP configuration files:

[AIX]     /etc/dhcpsd.cnf

[SLES]    /etc/dhcpd.conf

[RH]      /etc/dhcp/dhcpd.conf


********
SEE ALSO
********


noderange(3)|noderange.3

