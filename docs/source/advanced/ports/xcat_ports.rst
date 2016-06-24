Port Usage
==========

The following table lists the ports that must be open between the xCAT management node and the nodes it manages, unless otherwise noted. The xCAT service nodes use the same ports as the management node. A service (or protocol) applies to both AIX and Linux, unless stated otherwise. Service names are typical strings that appear in the /etc/services file, or in firewall/IP filtering logs. Local customization of the /etc/services files, daemon configuration options, like overriding the default port number, and differences in software source implementations, may yield other service information results.

The category of required or optional is difficult to fill in because depending on what function you are running what might be listed here as optional, may actually be required. The Trusted side is behind the firewall, the Non-trusted side is in front of the firewall.

xCAT Port Usage Table
---------------------

+--------------+-------------+-------------+------------+----------------------------------------+
|Service Name  |Port number  |Protocol     |Range       |Required or optional                    |
+==============+=============+=============+============+========================================+
|xcatdport     |3001         |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|xcatdport     |3001         |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|xcatiport     |3002         |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|xcatiport     |3002         |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|xcatlport     |3003(default)|tcp          |            |optional                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|echo-udp      |7            |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|ssh-tcp       |22           |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|ssh-udp       |22           |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|rsync         |873          |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|rsync         |873          |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|domain-tcp    |53           |tcp          |            |optional                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|domain-udp    |53           |udp          |            |optional                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|bootps        |67           |udp          |            |required on aix and p-linux             |
+--------------+-------------+-------------+------------+----------------------------------------+
|dhcp          |67           |tcp          |            |required on linux, optional on AIX      |
+--------------+-------------+-------------+------------+----------------------------------------+
|dhcpc         |68           |tcp          |            |required on linux, optional on AIX      |
+--------------+-------------+-------------+------------+----------------------------------------+
|bootpc        |68           |udp          |            |required on AIX                         |
+--------------+-------------+-------------+------------+----------------------------------------+
|tftp-tcp      |69           |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|tftp-udp      |69           |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|www-tcp       |80           |tcp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|www-udp       |80           |udp          |            |required                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|kerberos      |88           |tcp          |            |not supported/used by xCAT anymore      |
+--------------+-------------+-------------+------------+----------------------------------------+
|kerberos      |88           |udp          |            |not supported/used by xCAT anymore      |
+--------------+-------------+-------------+------------+----------------------------------------+
|sunrpc-udp    |111          |udp          |            |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|shell         |514          |tcp          |1-1023      |optional                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|rsyslogd      |514          |tcp          |            |required on linux                       |
+--------------+-------------+-------------+------------+----------------------------------------+
|rsyslogd      |514          |udp          |            |required on linux                       |
+--------------+-------------+-------------+------------+----------------------------------------+
|kshell        |544          |tcp          |1-1023      |required on AIX                         |
+--------------+-------------+-------------+------------+----------------------------------------+
|rmc-tcp       |657          |tcp          |1-1023      |required for RMC monitoring             |
+--------------+-------------+-------------+------------+----------------------------------------+
|rmc-udp       |657          |udp          |1-1023      |required for RMC monitoring             |
+--------------+-------------+-------------+------------+----------------------------------------+
|conserver     |782          |tcp          |            |required on the mgmt and service nodes  |
+--------------+-------------+-------------+------------+----------------------------------------+
|nim           |1058         |tcp          |1-1023      |required on AIX                         |
+--------------+-------------+-------------+------------+----------------------------------------+
|nfsd-tcp      |2049         |tcp          |1-1023      |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|nfsd-udp      |2049         |udp          |1-1023      |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|pxe           |4011         |tcp          |            |required for linux                      |
+--------------+-------------+-------------+------------+----------------------------------------+
|rpc-mount     |100005       |see Note2    |            |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|mount-tcp     |see Note1    |tcp          |            |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|mount-udp     |see Note1    |udp          |            |required on linux statelite and AIX     |
+--------------+-------------+-------------+------------+----------------------------------------+
|awk           |300          |tcp          |            |optional                                |
+--------------+-------------+-------------+------------+----------------------------------------+
|ipmi          |623          |tcp          |            |required on x86_64 and p8               |
+--------------+-------------+-------------+------------+----------------------------------------+
|ipmi          |623          |udp          |            |required on x86_64 and p8               |
+--------------+-------------+-------------+------------+----------------------------------------+
|snmp          |161          |tcp          |            |required on Flex                        |
+--------------+-------------+-------------+------------+----------------------------------------+
|snmp          |161          |udp          |            |required on Flex                        |
+--------------+-------------+-------------+------------+----------------------------------------+
|snmptrap      |162          |tcp          |            |required for snmp monitoring            |
+--------------+-------------+-------------+------------+----------------------------------------+
|snmptrap      |162          |udp          |            |required for snmp monitoring            |
+--------------+-------------+-------------+------------+----------------------------------------+

* xcatdport

  The port used by the xcatd daemon for client/server communication.

* xcatiport

  The port used by xcatd to receive install status updates from nodes.

* xcatlport

  The port used by xcatd to record command log, you can customize it by edit site table, if you don't configure it, 3003 will be used by default. 

* echo-udp

  Needed by RSCT Topology Services.

* ssh-udp

  Needed to use ssh. This service defines the protocol for upd. This is required when installing or running updatenode, xdsh,xdcp,psh,pcp through the firewall.

* rsync

  Need to use updatenode or xdcp to rsync files to the nodes or service nodes.

* domain-tcp

  Used when Domain Name Services (DNS) traffic from the Non-trusted nodes and the firewall node to a DNS server is explicitly handled by the firewall. Some firewall applications can be configured to explicitly handle all DNS traffic. This for tcp DNS traffic. 

* domain-udp 

  Used when Domain Name Services (DNS) traffic from the Non-trusted nodes and the firewall node to a DNS server is explicitly handled by the firewall. Some firewall applications can be configured to explicitly handle all DNS traffic. This for udp DNS traffic.

* bootps

  Bootp server port needed when installing an Non-trusted AIX or System p node through the firewall. This service is issued by the client to the Management Node , for an install request. It is not required to install the Non-trusted nodes through the firewall or to apply maintenance. This is the reason why the service is considered optional.

* dhcp

  Needed to install Linux nodes through the firewall. This is the port for the dhcp server. This service defines the protocol for tcp.

* dhcpc

  Needed to install Linux through the firewall. This is the port for the dhcp client. This service defines the protocol for tcp.

* bootpc

  Bootp client port needed when installing an Non-trusted AIX or System p node through the firewall. This service is issued by the Management Node back to the client, in response to an install request from the client. It is not required to install the Non-trusted nodes through the firewall or to apply maintenance. This is the reason why the service is considered optional.

* tftp-tcp

  Needed to install Linux nodes. This service defines the protocol for tcp.

* tftp-udp

  Needed to install Linux nodes. This service defines the protocol for udp.

* www-tcp

  Needed to use World Wide Web http.This service defines the protocol for tcp.

* www-udp

  Needed to use World Wide Web http. This service defines the protocol for udp.

* kerberos

  Kerberos Version 5 KDC. Needed if running Kerberos Version 5 remote command authentication. This service defines the protocol for tcp.

* kerberos

  Kerberos Version 5 KDC. Needed if running Kerberos Version 5 remote command authentication. This service defines the protocol for udp.

* sunrpc-udp

  The portmapper service. Needed when installing a Non-trusted node through the firewall. Specifically required mount request that takes place during node install. 

* shell 

  Used when rsh/rcp is enabled for Standard (std) authentication protocol. Needed for xdsh operations when using rsh for remote commands.

* rsyslogd

  Used for system log monitoring. This is for tcp protocol.

* rsyslogd

  Used for system log monitoring. This is for udp protocol.

* kshell

  Used rsh/rcp is enabled for Kerberos authentication. Not currently supported in xCAT. Network Installation Management client traffic generated by an Non-trusted node during node boot/shutdown. Required if using NIM. AIX only.

* rmc-tcp

  Resource Monitoring and Control (RMC) used for hardware monitoring, key exchange. This is for tcp protocol.

* rmc-udp

  Resource Monitoring and Control (RMC) used for hardware monitoring, key exchange. This is for udp protocol.

* conserver

  Required on the xCAT management node and service nodes. This service defines the protocol for tcp.

* nfsd-tcp

  Needed to use the AIX mount command. This service defines the protocol for tcp. Required when installing an Non-trusted node through the firewall. Needed when an installp is issued on an Non-trusted node and the resource exists on the Trusted side.

* nfsd-udp

  Needed to use the AIX mount command. This service defines the protocol for udp. Required when installing an Non-trusted node through the firewall.

* pxe

  Needed to install System x nodes through the firewall. This is the port for the PXE boot server. This service defines the protocol for tcp.

* rpc-mount

  Remote Procedure Call (RPM) used in conjunction with NFS mount request. See note 2. ssh-tcp Needed to use ssh. This service defines the protocol for tcp. This is required when installing or running updatenode through the firewall.
 
* mount-tcp

  Needed to use the AIX mount command. This service defines the protocol for tcp. Required when installing an Non-trusted node through the firewall. Needed when installp is issued on an Non-trusted node and the resource exists on the Trusted side. Needed to run updatenode command. See note 1.

* mount-udp

  Needed to use the AIX mount command. This service defines the protocol for udp. Needed when installp is issued on an Non-trusted node and the resource exists on the Trusted side. Needed to run updatenode command. See note 1.

* awk

  For awk communication during node discovery.

* impi

  For ipmi traffic.

* snmp

  For SNMP communication to blade chassis.

* snmptrap

  For SNMP communication to blade chassis.

Note 1 - AIX mount
``````````````````

On AIX, the mountd port range is usually determined at the time of the mount request. Part of the communication flow within a mount command is to query the remote mountd server and find out what ports it is using. The mountd ports are selected dynamically each time the mountd server is initialized. Therefore, the port numbers will vary from one boot to another, or when mountd is stopped and restarted.

Unfortunately, this causes a problem when used through a firewall, as no rule can be defined to handle traffic with a variable primary port. To create a service for mountd (server) traffic that has a fixed port, and one that can be trapped by a rule, you will need to update the /etc/services file on the host that is the target of the mount with new mountd entries for TCP and UDP, where the port numbers are known to be unused (free). The mountd TCP and UDP ports must be different. Any free port number is valid. The mountd must be stopped and started to pick up the new port values.

For example, issuing a mount request on Non-trusted node X, whose target is the Management Server, that is, ::

    mount ms2112:/images /images

would require that the /etc/services file on ms2112 be updated with something similar to the following: ::

    mountd 33333/tcp mountd 33334/udp

For mountd to detect its new port values you must stop and start rpc.mountd. The stopping and starting of mountd takes place on the same host where the /etc/services file mountd updates were made. In the above example, ms2112's mountd is stopped and started. You can verify that mountd is using the new port definitions by issuing the rpcinfo command.

This procedure shows how to change ports used by mountd: ::

    lssrc -s rpc.mountd

Produces output similar to: ::

    Subsystem Group PID Status rpc.mountd nfs 12404 active

Then ::

    rpcinfo -p ms2112 | grep mount

Produces output similar to: ::

    100005 1 udp 37395 mountd 100005 2 udp 37395 mountd 100005 3 udp 37395 mountd 100005 1 tcp 34095 mountd 100005 2 tcp 34095 mountd 100005 3 tcp 34095 mountd

Then :: 

    stopsrc -s rpc.mount

Produces output similar to: ::

    0513-044 The rpc.mountd Subsystem was requested to stop.

Update /etc/services with new mountd entries.

Note: Make a backup copy of /etc/services before making changes. ::

    grep mountd /etc/services

Produces output similar to: ::

    mountd 33333/tcp mountd 33334/udp

Then ::

    startsrc -s rpc.mountd

Produces output similar to: ::

    0513-059 The rpc.mountd Subsystem has been started. Subsystem PID is 19536.

Then ::

    rpcinfo -p ms2112 | grep mount

Produces output similar to: ::

    100005 1 udp 33334 mountd 100005 2 udp 33334 mountd 100005 3 udp 33334 mountd 100005 1 tcp 33333 mountd 100005 2 tcp 33333 mountd 100005 3 tcp 33333 mountd

Note 2
``````

The rpc-mount service differs from the other service definitions in the following way. There is no associated protocol, because by definition it is UDP based. There is no source port.
