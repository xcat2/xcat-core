Edgecore Switch
===============

The Edgecore switch from Mellanox is 1Gb top-of-rack switch. Usually, Mellanox ships the switch with Cumulus Network OS(https://cumulusnetworks.com) and along with a license file installed. In some case, user may get whitebox switch hardware without OS and license installed. 

Since edgecore switch is different from other traditional switches that xCAT supports, xCAT supports edgecore switch in a different way. Currently, the features provided by xCAT include: ::
  
  1) Cumulus Network OS provision
  2) switch discovery
  3) switch configuration:
     (a) enable root-passwordless ssh 
     (b) install licence file
     (c) enable snmp
  4) distribute files to switches with ``xdcp``
  5) invoke remote commands or scripts on switches with `xdsh``
  6) configure switches with ``updatenode``

This documentation presents a typical workflow on how to setup a edgecore switch from white box, then configure and manage the switch with xCAT.


Create a edgecore switch object
-------------------------------

If you have the information of the ip and mac information of the switch, the edgecore switch object definition can be created with the "cumulusswitch" template shipped in xCAT : ::
   
   mkdef edgecoresw1 --template cumulusswitch arch=armv71 ip=192.168.5.191 mac=8C:EA:1B:12:CA:40

Discover the switch

ONIE Mode
---------

If the switch arrives without an OS pre-loaded, the ONIE installer and management port is the only thing enabled on the switch. Once the switch connects to the xCAT network, the switch should get a dynamic IP address. The xCAT DHCP server will get requests from the onie-installer from the switch and attempt to find an OS binary file to execute. The following messages will be logged in /var/log/messages on the management node. ::

  Info: Fetching http://172.1.0.1/onie-installer-arm-accton_as4610_54-r0 ...
  Info: Fetching http://172.1.0.1/onie-installer-arm-accton_as4610_54 ...
  Info: Fetching http://172.1.0.1/onie-installer-accton_as4610_54 ...
  Info: Fetching http://172.1.0.1/onie-installer-arm ...
  Info: Fetching http://172.1.0.1/onie-installer .


To remove the installed Cumulus Linux OS to boot back to ONIE mode, connect to the switch via serial-port or ssh and execute the following commands: ::

  ssh cumulus@172.1.0.1
  #clean up all the configuration
  sudo onie-select -k
  sudo reboot
  #boot back to onie mode
  sudo onie-select -i
  sudo reboot


After switch reboots, it will enter ONIE mode and send DHCP request to attempt to fetch the OS binary file.


Discover Edgecore Switch
------------------------

ONIE supports a number of methods for locating OS binary file.  xCAT choose to use a DHCP server to provide specific information to the switch.  

* IP address of the switch
* URL of the OS binary file on the Web server

With the xCAT DHCP configuration, ONIE picks up an IP address and downloads the URL specified by the user and start to install of the OS.  The steps take to discover the edgecore switch and process request from ONIE installer as follows:

#. Pre-define switch object into xCAT db, make sure ip adress, netboot and provemethod are set, also define core switch and port number where edgecore switch connect to. ::


      #lsdef edgecoresw1
      Object name: edgecoresw1
        groups=switch
        ip=192.168.23.1
        mgt=switch
        netboot=onie
        nodetype=switch
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        provmethod=/install/custom/sw/edgecore/cumulus-linux-3.1.0-bcm-armel-1471981017.dc7e2adzfb43f6b.bin
        switch=switch-10-5-23-1
        switchport=1

      #makehosts edgecoresw1


#. Run ``switchdiscover`` command,  it will find edgecore switch and update mac address on pre-defined switch node definition.  ::

    #switchdiscover --range 192.168.5.170-190 -s nmap
    #lsdef edgecoresw1
    Object name: edgecoresw1
        groups=switch
        ip=192.168.23.1
        mac=8C:EA:1B:12:CA:40
        mgt=switch
        netboot=onie
        nodetype=switch
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        provmethod=/install/custom/sw/edgecore/cumulus-linux-3.1.0-bcm-armel-1471981017.dc7e2adzfb43f6b.bin
        status=Matched
        switch=switch-10-5-23-1
        switchport=1
        switchtype=cumulus
        usercomment=Edgecore switch


#. Run ``makedhcp`` after edgecore switch discovered,  it will update ``dhcpd.conf`` and response the DHCP request from the onie-installer.  ::
  
    #makedhcp -n
    #makedhcp -a edgecoresw1


#.  Installation of the Cumulus Linux OS takes about 50 minutes. Monitor the /var/log/messages to check the status of the installation.  ::


    Oct 27 15:28:08 fs4 dhcpd: DHCPDISCOVER from 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPOFFER on 192.168.23.1 to 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPREQUEST for 192.168.23.1 (192.168.3.25) from 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPACK on 192.168.23.1 to 8c:ea:1b:12:ca:40 via enP4p1s0f2


#.  Once installation finished, the pre-defined switch name and IP address will be configured on edgecore switch. ::

    cumulus@edgecoresw1:~$ ifconfig
    eth0      Link encap:Ethernet  HWaddr 8c:ea:1b:12:ca:40
              inet addr:192.168.23.1  Bcast:192.168.255.255  Mask:255.255.0.0
              inet6 addr: fe80::8eea:1bff:fe12:ca40/64 Scope:Link
              UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
    cumulus@edgecoresw1:~$ hostname
    edgecoresw1  


Configure Edgecore Switch
-------------------------

xCAT provides a script ``/opt/xcat/share/xcat/script/configcumulus`` to configure attributes in the Cumulus Switch. Use the ``--help`` option to see more details.  ::

  #configcumulus --help
  Usage:
    configcumulus [-?│-h│--help]
    configcumulus [--switches switchnames] [--all]
    configcumulus [--switches switchnames] [--ssh]
    configcumulus [--switches switchnames] [--license filename ]
    configcumulus [--switches switchnames] [--snmp] [--user snmp_user] [--password snmp_password]
    configcumulus [--switches switchnames] [--ntp]

 





 
