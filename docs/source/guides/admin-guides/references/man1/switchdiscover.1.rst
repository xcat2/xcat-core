
################
switchdiscover.1
################

.. highlight:: perl


********
SYNOPSIS
********


\ **switchdiscover [-h| -**\ **-help]**\ 

\ **switchdiscover [-v| -**\ **-version]**\ 

\ **switchdiscover**\  [\ *noderange*\  | \ **-**\ **-range**\  \ *ip_ranges*\ ] \ **[-V] [-w][-r|-x|-z][-s**\  \ *scan_methods*\  \ **-**\ **-setup**\ ]


***********
DESCRIPTION
***********


The switchdiscover command scans the subnets and discovers all the swithches on the subnets. The command takes a list of subnets as input. The default subnets are the ones that the xCAT management node is on. It uses nmap command as default to discover the switches. However, you can specify other discovery methods such as lldp or snmp with \ **-s**\  flag. You can write the discovered switches into xCAT database with \ **-w**\  flag. This command supports may output formats such as xml(\ **-x**\ ), raw(\ **-r**\ ) and stanza(\ **-z**\ ) in addition to the default format.

\ **-**\ **-setup**\  flag is for switch-based switch discovery.  It will find all the discovered switches on the subnets, then match them with predefined switches in the xCATDB. Next, it will set discovered switches with static ip address and hostname based on the predefined switch.  It will also enable snmpv3 configuration. The details of the process are defined in the http://xcat-docs.readthedocs.io/en/latest/advanced/networks/switchdiscover/switches_discovery.html.

To view all the switches defined in the xCAT databasee use \ **lsdef -w "nodetype=switch"**\  command.

For lldp method, make sure that lldpd package is installed and lldpd is running on the xCAT management node. lldpd comes from xcat-dep packge or you can get it from http://vincentbernat.github.io/lldpd/installation.html.

For snmp method, make sure that snmpwalk command is installed and snmp is enabled for switches. To install snmpwalk, "yum install net-snmp-utils" for redhat and sles,  "apt-get install snmp" for Ubuntu.


*******
OPTIONS
*******



\ *noderange*\ 
 
 The switches which the user want to discover.
 If the user specify the noderange, switchdiscover will just
 return the switches in the node range. Which means it will 
 help to add the new switches to the xCAT database without
 modifying the existed definitions. But the switches' name 
 specified in noderange should be defined in database in advance. 
 The ips of the switches will be defined in /etc/hosts file. 
 This command will fill the switch attributes for the switches defined.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-**\ **-range**\ 
 
 Specify one or more IP ranges. Each can be an ip address (10.1.2.3) or an ip range (10.1.2.0/24). If the range is huge, for example, 192.168.1.1/8, the switch discover may take a very long time to scan. So the range should be exactly specified.
 
 For nmap and snmp scan method, it accepts multiple formats. For example: 192.168.1.1/24, 40-41.1-2.3-4.1-100.
 
 If the range is not specified, the command scans all the subnets that the active network interfaces (eth0, eth1) are on where this command is issued.
 


\ **-r**\ 
 
 Display Raw responses.
 


\ **-s**\ 
 
 It is a comma separated list of methods for switch discovery. 
 The possible switch scan methods are: lldp, nmap or snmp. The default is nmap.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-V**\ 
 
 Verbose output.
 


\ **-w**\ 
 
 Writes output to xCAT database.
 


\ **-x**\ 
 
 XML formated output.
 


\ **-z**\ 
 
 Stanza formated output.
 


\ **-**\ **-setup**\ 
 
 Process switch-based switch discovery. Update discovered switch's ip address, hostname and enable snmpv3 configuration based on the predefined switch.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1. To discover the switches on some subnets:
 
 
 .. code-block:: perl
 
   switchdiscover --range 10.2.3.0/24,192.168.3.0/24,11.5.6.7
 
 


2. To do the switch discovery and save them to the xCAT database:
 
 
 .. code-block:: perl
 
   switchdiscover --range 10.2.3.4/24 -w
 
 
 It is recommended to run \ **makehosts**\  after the switches are saved in the DB.
 


3. To use lldp method to discover the switches:
 
 
 .. code-block:: perl
 
   switchdiscover -s lldp
 
 


4. To process switch-based switch discovery, the core switch has to be configured and top-of-rack (edge) switch has to be predefine into xCAT databse with attribute \ **switch**\  and \ **switchport**\  to core switch:
 
 
 .. code-block:: perl
 
   switchdiscover --range 192.168.5.150-170 -s snmp --setup
 
 



*****
FILES
*****


/opt/xcat/bin/switchdiscover


********
SEE ALSO
********


