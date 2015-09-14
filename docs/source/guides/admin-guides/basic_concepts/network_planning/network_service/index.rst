Network Services
================

The following network services are used by xCAT:

DNS(Domain Name Service)
------------------------
The dns server, usually the management node or service node, provides the domain name service for the entire cluster.

HTTP(HyperText Transfer Protocol)
---------------------------------
The http server,usually the management node or service node, acts as the download server for the initrd and kernel, the configuration file for the installer and repository for the online installation.  

DHCP(Dynamic Host Configuration Protocol)
-----------------------------------------
The dhcp server,usually the management node or service node, privides the dhcp service for the entire cluster.

TFTP(Trivial File Transfer Protocol)
------------------------------------
The tftp server,usually the management node or service node, acts as the download server for bootloader binaries, bootloader configuration file, initrd and kernel.

NFS(Network File System)
------------------------
The NFS server, usually the management node or service node, provides the file system sharing between the management node and service node, or persistent file system support for the stateless node. 

NTP(Network Time Protocol)
--------------------------
The NTP server, usually the management node or service node, provide the network time service for the entire cluster.

SYSLOG
------
Usually, xCAT uses rsyslog as the syslog service for the cluster, all the log messages of the nodes in the cluster are forwarded to the management node. 



