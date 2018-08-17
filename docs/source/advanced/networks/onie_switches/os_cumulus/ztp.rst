Setup ONIE switches with ZTP in large cluster
=============================================

Zero Touch Provisioning  (ZTP) is a feature shipped in many network devices to enable them to be quickly deployed in large-scale environments. In Cumulus OS on ONIE switches with ZTP enabled, the URL of an user provided script can be specified in the DHCP response for the DHCP request trigged by one of the following events:

    * Booting the switch
    * Plugging a cable into or unplugging it from the eth0 port
    * Disconnecting then reconnecting the switch's power cord.

the script will be then downloaded and executed on the network device.

Leveraging the ZTP mechanism, xCAT provides the capability to setup ONIE switches from white-box without touching anything, including Cumulus OS installation, discovery and configuration. Please follow the steps below to setup ONIE switches in the cluster:

1. Ensure that xCAT is configured with an DHCP open range to detect when new switches request DHCP IPs

   (1). Make sure the network in which the management interface of the ONIE switches are connected has been defined in ``networks`` table ::

       # tabdump networks
       #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,comments,disable
       "172_21_0_0-255_255_0_0","172.21.0.0","255.255.0.0","enP3p3s0d1","<xcatmaster>","172.21.253.27","172.21.253.27",,,,"172.21.253.100-172.21.253.200",,,,,,,,,

   (2). Prepare the DHCP configuration for ONIE switches setup

      Add the management node's NIC facing the ONIE switches' management interface to the ``site.dhcpinterfaces`` ::

        chdef -t site -p dhcpinterfaces=enP3p3s0d1

      Add dynamic range for the temporary IP addresses used in the OS provision and discovery of ONIE switches ::

        chdef -t network 172_21_0_0-255_255_0_0 dynamicrange="172.21.253.100-172.21.253.200"

      Update DHCP configuration file ::

        makedhcp -n

2. Predefine ONIE switches according to the network plan ::

     mkdef mid05tor10 --template onieswitch ip=172.21.205.10 switch=mgmtsw01 switchport=10

   ``ip`` is the IP address of the management interface of the ONIE switch

   ``switch`` is the core switch to which the management interface of ONIE switch is connected.

   ``switchport`` is the port on the core switch to which the management interface of ONIE switch is connected.

3. Add the predefined switches into ``/etc/hosts`` ::

     makehosts mid05tor10

4. [If the Cumulus OS have been installed on the ONIE switches, please skip this step] Prepare the Cumulus installation image, ``/install/onie/onie-installer`` is the hard-coded path of the Cumulus installation image, or the link to the Cumulus installation image on the management node ::

     mkdir -p /install/onie/
     cp /install/custom/sw_os/cumulus/cumulus-linux-3.1.0-bcm-armel.bin /install/onie/
     ln -s /install/onie/cumulus-linux-3.1.0-bcm-armel.bin /install/onie/onie-installer

5. Plug the ONIE switches into the cluster according to the network plan and power on them.

   For the white-box ONIE switches, the Cumulus OS will be installed, then the switches will be discovered and configured automaticaly, the whole process will take about 1 hour.

   For the ONIE switches already with Cumulus OS installed, please make sure the ZTP have been enabled and none of the following manual configuration have been made:

   * Password changes
   * Users and groups changes
   * Packages changes
   * Interfaces changes
   * The presence of an installed license

   Otherwise, please run ``ztp -R`` on the switches to reset the ZTP state before switch boot up for setup. The whole setup process will take about 1-2 minutes.

6. The switch definition in xCAT will be updated when the switch is configured ::

     # lsdef mid05tor10
     Object name: mid05tor10
         arch=armv7l
         groups=switch
         ip=172.21.205.10
         mac=xx:xx:xx:xx:xx:xx
         mgt=switch
         netboot=onie
         nodetype=switch
         postbootscripts=otherpkgs
         postscripts=syslog,remoteshell,syncfiles
         serial=11S01FT690YA50YD73EACH
         status=configured
         statustime=06-22-2017 23:14:14
         supportedarchs=armv7l
         switch=mgmtsw01
         switchport=10
         switchtype=Edgecore Networks Switch

   ``status=configured`` indicates that the switch has been discovered and configured.
