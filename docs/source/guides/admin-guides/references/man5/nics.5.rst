
######
nics.5
######

.. highlight:: perl


****
NAME
****


\ **nics**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nics Attributes:**\   \ *node*\ , \ *nicips*\ , \ *nichostnamesuffixes*\ , \ *nichostnameprefixes*\ , \ *nictypes*\ , \ *niccustomscripts*\ , \ *nicnetworks*\ , \ *nicaliases*\ , \ *nicextraparams*\ , \ *nicdevices*\ , \ *nicsadapter*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Stores NIC details.


****************
nics Attributes:
****************



\ **node**\ 
 
 The node or group name.
 


\ **nicips**\ 
 
 Comma-separated list of IP addresses per NIC. 
                 To specify one ip address per NIC:
                     <nic1>!<ip1>,<nic2>!<ip2>,..., for example, eth0!10.0.0.100,ib0!11.0.0.100
                 To specify multiple ip addresses per NIC:
                     <nic1>!<ip1>|<ip2>,<nic2>!<ip1>|<ip2>,..., for example, eth0!10.0.0.100|fd55::214:5eff:fe15:849b,ib0!11.0.0.100|2001::214:5eff:fe15:849a. The xCAT object definition commands support to use nicips.<nicname> as the sub attributes.
                 Note: The primary IP address must also be stored in the hosts.ip attribute. The nichostnamesuffixes should specify one hostname suffix for each ip address.
 


\ **nichostnamesuffixes**\ 
 
 Comma-separated list of hostname suffixes per NIC. 
                         If only one ip address is associated with each NIC:
                             <nic1>!<ext1>,<nic2>!<ext2>,..., for example, eth0!-eth0,ib0!-ib0
                         If multiple ip addresses are associated with each NIC:
                             <nic1>!<ext1>|<ext2>,<nic2>!<ext1>|<ext2>,..., for example,  eth0!-eth0|-eth0-ipv6,ib0!-ib0|-ib0-ipv6. 
                         The xCAT object definition commands support to use nichostnamesuffixes.<nicname> as the sub attributes. 
                         Note:  According to DNS rules a hostname must be a text string up to 24 characters drawn from the alphabet (A-Z), digits (0-9), minus sign (-),and period (.). When you are specifying "nichostnamesuffixes" or "nicaliases" make sure the resulting hostnames will conform to this naming convention
 


\ **nichostnameprefixes**\ 
 
 Comma-separated list of hostname prefixes per NIC. 
                         If only one ip address is associated with each NIC:
                             <nic1>!<ext1>,<nic2>!<ext2>,..., for example, eth0!eth0-,ib0!ib-
                         If multiple ip addresses are associated with each NIC:
                             <nic1>!<ext1>|<ext2>,<nic2>!<ext1>|<ext2>,..., for example,  eth0!eth0-|eth0-ipv6i-,ib0!ib-|ib-ipv6-. 
                         The xCAT object definition commands support to use nichostnameprefixes.<nicname> as the sub attributes. 
                         Note:  According to DNS rules a hostname must be a text string up to 24 characters drawn from the alphabet (A-Z), digits (0-9), minus sign (-),and period (.). When you are specifying "nichostnameprefixes" or "nicaliases" make sure the resulting hostnames will conform to this naming convention
 


\ **nictypes**\ 
 
 Comma-separated list of NIC types per NIC. <nic1>!<type1>,<nic2>!<type2>, e.g. eth0!Ethernet,ib0!Infiniband. The xCAT object definition commands support to use nictypes.<nicname> as the sub attributes.
 


\ **niccustomscripts**\ 
 
 Comma-separated list of custom scripts per NIC.  <nic1>!<script1>,<nic2>!<script2>, e.g. eth0!configeth eth0, ib0!configib ib0. The xCAT object definition commands support to use niccustomscripts.<nicname> as the sub attribute
 .
 


\ **nicnetworks**\ 
 
 Comma-separated list of networks connected to each NIC.
                 If only one ip address is associated with each NIC:
                     <nic1>!<network1>,<nic2>!<network2>, for example, eth0!10_0_0_0-255_255_0_0, ib0!11_0_0_0-255_255_0_0
                 If multiple ip addresses are associated with each NIC:
                     <nic1>!<network1>|<network2>,<nic2>!<network1>|<network2>, for example, eth0!10_0_0_0-255_255_0_0|fd55:faaf:e1ab:336::/64,ib0!11_0_0_0-255_255_0_0|2001:db8:1:0::/64. The xCAT object definition commands support to use nicnetworks.<nicname> as the sub attributes.
 


\ **nicaliases**\ 
 
 Comma-separated list of hostname aliases for each NIC.
                 Format: eth0!<alias list>,eth1!<alias1 list>|<alias2 list>
                     For multiple aliases per nic use a space-separated list. 
                 For example: eth0!moe larry curly,eth1!tom|jerry
 


\ **nicextraparams**\ 
 
 Comma-separated list of extra parameters that will be used for each NIC configuration.
                 If only one ip address is associated with each NIC:
                     <nic1>!<param1=value1 param2=value2>,<nic2>!<param3=value3>, for example, eth0!MTU=1500,ib0!MTU=65520 CONNECTED_MODE=yes.
                 If multiple ip addresses are associated with each NIC:
                     <nic1>!<param1=value1 param2=value2>|<param3=value3>,<nic2>!<param4=value4 param5=value5>|<param6=value6>, for example, eth0!MTU=1500|MTU=1460,ib0!MTU=65520 CONNECTED_MODE=yes.
             The xCAT object definition commands support to use nicextraparams.<nicname> as the sub attributes.
 


\ **nicdevices**\ 
 
 Comma-separated list of NIC device per NIC, multiple ethernet devices can be bonded as bond device, these ethernet devices are separated by | . <nic1>!<dev1>|<dev3>,<nic2>!<dev2>, e.g. bond0!eth0|eth2,br0!bond0. The xCAT object definition commands support to use nicdevices.<nicname> as the sub attributes.
 


\ **nicsadapter**\ 
 
 Comma-separated list of extra parameters that will be used for each NIC configuration.
                     <nic1>!<param1=value1 param2=value2>|<param3=value3>,<nic2>!<param4=value4 param5=value5>|<param6=value6>, for example, eth0!MTU=1500|MTU=1460,ib0!MTU=65520 CONNECTED_MODE=yes.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

