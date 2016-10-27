Edgecode switch
===============

The Edgecore switch from Mellanox is 1Gb top-of-rack switch.  It's coming with ONIE installer.  ONIE is stanford Open Network Install Environment and allow end-users to install the target network OS on switch.  Mellanox will ship the switch with Cumulus Network OS and along with a license file installed. In some case, user may get whitebox without OS and licenses.  Since edgecore switch has different configuration than other switches that xCAT supports, xCAT handles edgecore switch differently.


ONIE mode
----------

If the switch arrives only  with firmware, ONIE installer and management port is enabled on the switch.  Once connect to xCAT network, the switch will get dynamic address.  The xCAT dhcp server will get request from onie-installer of the switch and ONIE will attempt to find OS binary file to execute. Those messages will be logged in the /var/log/messages on XCAT MN. ::

  Info: Fetching http://172.1.0.1/onie-installer-arm-accton_as4610_54-r0 ...
  Info: Fetching http://172.1.0.1/onie-installer-arm-accton_as4610_54 ...
  Info: Fetching http://172.1.0.1/onie-installer-accton_as4610_54 ...
  Info: Fetching http://172.1.0.1/onie-installer-arm ...
  Info: Fetching http://172.1.0.1/onie-installer .


If the switch arrives with cumulus OS installed and likes to boot back into ONIE, user can get to switch via serial-port or ssh to switch if knows switch ip address. ::

  ssh cumulus@172.1.0.1
  #clean up all the configuration
  sudo onie-select -k
  sudo reboot
  #boot back to onie mode
  sudo onie-select -i
  sudo reboot


After switch bootes,  it will went to ONIE mode and send DHCP request to fetching the OS binary file.

Discover Edgecore Switch
------------------------

ONIE supports a number of methods for locating OS binary file.  xCAT choose to use a DHCP server to provide specific information to the switch.  

* IP address of the switch
* URL of the OS binary file on the Web server

with the xCAT dhcp configuration, ONIE picks up an IP address and download the URL specified by the user and start to install the OS.  The steps take to discover the edgecore switch and process request from ONIE installer as follows:

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


#. run switchdiscover command,  it will find edgecore switch and update mac address on pre-defined switch node defintion.  ::

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


#. run makedhcp after edgecore switch discovered,  it will update dhcpd.conf and response the dhcp request from the onie-installer.  ::
  
    #makedhcp -n
    #makedhcp -a edgecoresw1


#.  after makedhcp,  onie-installer will located the OS binary file and start up installation. Installation will take about 50 mins.  currently, we didn't find a good way to know when installation is finished.  user can check /var/log/messages.  The DHCP discover message will be logged from edgecore switch's mac address.  ::


    Oct 27 15:28:08 fs4 dhcpd: DHCPDISCOVER from 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPOFFER on 192.168.23.1 to 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPREQUEST for 192.168.23.1 (192.168.3.25) from 8c:ea:1b:12:ca:40 via enP4p1s0f2
    Oct 27 15:28:08 fs4 dhcpd: DHCPACK on 192.168.23.1 to 8c:ea:1b:12:ca:40 via enP4p1s0f2


#.  Once installation finished, the pre-sefined switch name and ip address will be set on edgecore switch. ::

    cumulus@edgecoresw1:~$ ifconfig
    eth0      Link encap:Ethernet  HWaddr 8c:ea:1b:12:ca:40
              inet addr:192.168.23.1  Bcast:192.168.255.255  Mask:255.255.0.0
              inet6 addr: fe80::8eea:1bff:fe12:ca40/64 Scope:Link
              UP BROADCAST RUNNING MULTICAST  MTU:1500  Metric:1
    cumulus@edgecoresw1:~$ hostname
    edgecoresw1  


Configure edgecore switch
-------------------------

xCAT provide a configure file /opt/xcat/share/xcat/script/configcumulus to configure passwordless ssh, install cumulus license, setup snmpv3 and ntp.  ::

  #configcumulus --help
  Usage:
    configcumulus [-?│-h│--help]
    configcumulus [--switches switchnames] [--all]
    configcumulus [--switches switchnames] [--ssh]
    configcumulus [--switches switchnames] [--license filename ]
    configcumulus [--switches switchnames] [--snmp] [--user snmp_user] [--password snmp_password]
    configcumulus [--switches switchnames] [--ntp]

 





 
