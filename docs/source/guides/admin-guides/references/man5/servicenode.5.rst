
#############
servicenode.5
#############

.. highlight:: perl


****
NAME
****


\ **servicenode**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **servicenode Attributes:**\   \ *node*\ , \ *nameserver*\ , \ *dhcpserver*\ , \ *tftpserver*\ , \ *nfsserver*\ , \ *conserver*\ , \ *monserver*\ , \ *ldapserver*\ , \ *ntpserver*\ , \ *ftpserver*\ , \ *nimserver*\ , \ *ipforward*\ , \ *dhcpinterfaces*\ , \ *proxydhcp*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


List of all Service Nodes and services that will be set up on the Service Node.


***********************
servicenode Attributes:
***********************



\ **node**\ 
 
 The hostname of the service node as known by the Management Node.
 


\ **nameserver**\ 
 
 Do we set up DNS on this service node? Valid values: 2, 1, no or 0. If 2, creates named.conf as dns slave, using the management node as dns master, and starts named. If 1, creates named.conf file with forwarding to the management node and starts named. If no or 0, it does not change the current state of the service.
 


\ **dhcpserver**\ 
 
 Do we set up DHCP on this service node? Not supported on AIX. Valid values:yes or 1, no or 0. If yes, runs makedhcp -n. If no or 0, it does not change the current state of the service.
 


\ **tftpserver**\ 
 
 Do we set up TFTP on this service node? Not supported on AIX. Valid values:yes or 1, no or 0. If yes, configures and starts atftp. If no or 0, it does not change the current state of the service.
 


\ **nfsserver**\ 
 
 Do we set up file services (HTTP,FTP,or NFS) on this service node? For AIX will only setup NFS, not HTTP or FTP. Valid values:yes or 1, no or 0.If no or 0, it does not change the current state of the service.
 


\ **conserver**\ 
 
 Do we set up Conserver on this service node?  Valid values:yes or 1, no or 0. If yes, configures and starts conserver daemon. If no or 0, it does not change the current state of the service.
 


\ **monserver**\ 
 
 Is this a monitoring event collection point? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.
 


\ **ldapserver**\ 
 
 Do we set up ldap caching proxy on this service node? Not supported on AIX.  Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.
 


\ **ntpserver**\ 
 
 Not used. Use setupntp postscript to setup a ntp server on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.
 


\ **ftpserver**\ 
 
 Do we set up a ftp server on this service node? Not supported on AIX Valid values:yes or 1, no or 0. If yes, configure and start vsftpd.  (You must manually install vsftpd on the service nodes before this.) If no or 0, it does not change the current state of the service. xCAT is not using ftp for compute nodes provisioning or any other xCAT features, so this attribute can be set to 0 if the ftp service will not be used for other purposes
 


\ **nimserver**\ 
 
 Not used. Do we set up a NIM server on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.
 


\ **ipforward**\ 
 
 Do we set up ip forwarding on this service node? Valid values:yes or 1, no or 0. If no or 0, it does not change the current state of the service.
 


\ **dhcpinterfaces**\ 
 
 The network interfaces DHCP server should listen on for the target node. This attribute can be used for management node and service nodes.  If defined, it will override the values defined in site.dhcpinterfaces. This is a comma separated list of device names. !remote! indicates a non-local network for relay DHCP. For example: !remote!,eth0,eth1
 


\ **proxydhcp**\ 
 
 Do we set up proxydhcp service on this node? valid values: yes or 1, no or 0. If yes, the proxydhcp daemon will be enabled on this node.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

