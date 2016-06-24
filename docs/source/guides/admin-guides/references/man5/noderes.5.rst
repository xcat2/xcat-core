
#########
noderes.5
#########

.. highlight:: perl


****
NAME
****


\ **noderes**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **noderes Attributes:**\   \ *node*\ , \ *servicenode*\ , \ *netboot*\ , \ *tftpserver*\ , \ *tftpdir*\ , \ *nfsserver*\ , \ *monserver*\ , \ *nfsdir*\ , \ *installnic*\ , \ *primarynic*\ , \ *discoverynics*\ , \ *cmdinterface*\ , \ *xcatmaster*\ , \ *current_osimage*\ , \ *next_osimage*\ , \ *nimserver*\ , \ *routenames*\ , \ *nameservers*\ , \ *proxydhcp*\ , \ *syslog*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Resources and settings to use when installing nodes.


*******************
noderes Attributes:
*******************



\ **node**\ 
 
 The node name or group name.
 


\ **servicenode**\ 
 
 A comma separated list of node names (as known by the management node) that provides most services for this node. The first service node on the list that is accessible will be used.  The 2nd node on the list is generally considered to be the backup service node for this node when running commands like snmove.
 


\ **netboot**\ 
 
 The type of network booting to use for this node.  Valid values:
 
 
 .. code-block:: perl
 
                         Arch                    OS                           valid netboot options 
                         x86, x86_64             ALL                          pxe, xnba 
                         ppc64                   <=rhel6, <=sles11.3          yaboot
                         ppc64                   >=rhels7, >=sles11.4         grub2,grub2-http,grub2-tftp
                         ppc64le NonVirtualize   ALL                          petitboot
                         ppc64le PowerKVM Guest  ALL                          grub2,grub2-http,grub2-tftp
 
 


\ **tftpserver**\ 
 
 The TFTP server for this node (as known by this node). If not set, it defaults to networks.tftpserver.
 


\ **tftpdir**\ 
 
 The directory that roots this nodes contents from a tftp and related perspective.  Used for NAS offload by using different mountpoints.
 


\ **nfsserver**\ 
 
 The NFS or HTTP server for this node (as known by this node).
 


\ **monserver**\ 
 
 The monitoring aggregation point for this node. The format is "x,y" where x is the ip address as known by the management node and y is the ip address as known by the node.
 


\ **nfsdir**\ 
 
 The path that should be mounted from the NFS server.
 


\ **installnic**\ 
 
 The network adapter on the node that will be used for OS deployment, the installnic can be set to the network adapter name or the mac address or the keyword "mac" which means that the network interface specified by the mac address in the mac table will be used.  If not set, primarynic will be used. If primarynic is not set too, the keyword "mac" will be used as default.
 


\ **primarynic**\ 
 
 This attribute will be deprecated. All the used network interface will be determined by installnic. The network adapter on the node that will be used for xCAT management, the primarynic can be set to the network adapter name or the mac address or the keyword "mac" which means that the network interface specified by the mac address in the mac table  will be used.  Default is eth0.
 


\ **discoverynics**\ 
 
 If specified, force discovery to occur on specific network adapters only, regardless of detected connectivity.  Syntax can be simply "eth2,eth3" to restrict discovery to whatever happens to come up as eth2 and eth3, or by driver name such as "bnx2:0,bnx2:1" to specify the first two adapters managed by the bnx2 driver
 


\ **cmdinterface**\ 
 
 Not currently used.
 


\ **xcatmaster**\ 
 
 The hostname of the xCAT service node (as known by this node).  This acts as the default value for nfsserver and tftpserver, if they are not set.  If xcatmaster is not set, the node will use whoever responds to its boot request as its master.  For the directed bootp case for POWER, it will use the management node if xcatmaster is not set.
 


\ **current_osimage**\ 
 
 Not currently used.  The name of the osimage data object that represents the OS image currently deployed on this node.
 


\ **next_osimage**\ 
 
 Not currently used.  The name of the osimage data object that represents the OS image that will be installed on the node the next time it is deployed.
 


\ **nimserver**\ 
 
 Not used for now. The NIM server for this node (as known by this node).
 


\ **routenames**\ 
 
 A comma separated list of route names that refer to rows in the routes table. These are the routes that should be defined on this node when it is deployed.
 


\ **nameservers**\ 
 
 An optional node/group specific override for name server list.  Most people want to stick to site or network defined nameserver configuration.
 


\ **proxydhcp**\ 
 
 To specify whether the node supports proxydhcp protocol. Valid values: yes or 1, no or 0. Default value is yes.
 


\ **syslog**\ 
 
 To configure how to configure syslog for compute node. Valid values:blank(not set), ignore. blank - run postscript syslog; ignore - do NOT run postscript syslog
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

