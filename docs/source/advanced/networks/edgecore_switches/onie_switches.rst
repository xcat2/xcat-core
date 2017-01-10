ONIE compatible bare metal switch
=================================

The ONIE [1]_. compatible bare metal switches(abbreviated as "ONIE switch") from vendors such as Mellanox or Edgecore are often used as top-of-rack switches in the cluster. Usually, the switches are shipped with a Cumulus Network OS(https://cumulusnetworks.com) and a license pre-installed. In some cases, user may get whitebox switch hardware with a standalone Cumulus installer and license file. This documentation presents a typical workflow on how to setup ONIE switch from white box, then configure and manage the switch with xCAT. 
  
.. [1] Open Network Install Environment: Created by Cumulus Networks, Inc. in 2012, the Open Network Install Environment (ONIE) Project is a small operating system, pre-installed as firmware on bare metal network switches, that provides an environment for automated operating system provisioning.

Create an ONIE switch object
-------------------------------

The ONIE switch object can be created with the "onieswitch" template shipped in xCAT, the ip address and mac of the switch management ethernet port should be specified : :: 

   mkdef edgecoresw1 --template onieswitch arch=armv71 ip=192.168.5.191 mac=8C:EA:1B:12:CA:40

Provision the Cumulus OS on ONIE switch
---------------------------------------

To provision Cumulus OS, the Cumulus installation file, a binary shipped with the switch, should be saved in a directory exported in the http server. 

Run ``chdef`` to specify the "provmethod" attribute of the switch object to the full path of the installation file: ::

   chdef edgecoresw1 netboot=onie provmethod="/install/custom/sw/edgecore/cumulus-linux-3.1.0-bcm-armel-1471981017.dc7e2adzfb43f6b.bin" 

Run ``makedhcp`` to prepare the DHCP/BOOTP lease. ::

   makedhcp -a edgecoresw1

The command or operation to start the provision dependes on the status of switch:

1. If the switch is a white box without Cumulus OS installed, simply connect the management ethernet port of the switch to xCAT management node, then power on the switch.

2. If a Cumulus OS has been installed on the switch, you need to login to the switch(the default user is ``cumulus`` and the password is ``CumulusLinux!``) and run a batch of commands: ::
   
      sudo onie-select -i
      sudo reboot
  
If the passwordless-ssh of "root" has been enabled, the commands can be issued with: ::
      
   xdsh edgecoresw1 "/usr/cumulus/bin/onie-select -i -f;reboot"

After reboot, the switch will enter ONIE install mode and begin the installation. The provision might take about 50 minutes. 

    
Switch Configuration
--------------------   

Enable the passwordless ssh for "root"
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In a newly installed Cumulus OS, a default user ``cumulus`` will be created, the switch can be accessed via ssh with the default password ``CumulusLinux!``. 

The passwordless ssh access of "root" should be enabled with the script ``/opt/xcat/share/xcat/scripts/configcumulus`` ::

    /opt/xcat/share/xcat/scripts/configcumulus --switches edgecoresw1 --ssh

After the passwordless access for "root" is setup successfully, the switch can be managed with the node management commands such as ``xdsh``, ``xdcp`` and ``updatenode``, etc.
 
Licence file installation
~~~~~~~~~~~~~~~~~~~~~~~~~

On the newly installed switch, only the serial console and the management ethernet port are enabled. To activate the data ports, the licence file shipped with the switch should be installed: ::
 
   xdcp edgecoresw1 /install/custom/sw/edgecore/licensefile.txt /tmp
   xdsh edgecoresw1 "/usr/cumulus/bin/cl-license -i /tmp/licensefile.txt" 

To check whether the license file is installed successfully: ::

   ~: xdsh edgecoresw1 /usr/cumulus/bin/cl-license
   edgecoresw1: xxx@xx.com|xxxxxxxxxxxxxxx

Reboot the switch to apply the licence file: ::

   xdsh edgecoresw1 reboot

Enable SNMP
~~~~~~~~~~~

The snmpd in the switch is not enabled by default, xCAT ships a postscript to enable it: ::
   
   updatenode edgecoresw1 -P enablesnmp


Switch Discovery
----------------

The ONIE switch can be scaned and discovered with ``switchdiscover`` ::
    
   ~: switchdiscover --range 192.168.23.1-10
   Discovering switches using nmap for 192.168.23.1-10. It may take long time...
   ip              name                    vendor                                                  mac
   ------------    ------------            ------------                                            ------------
   192.168.23.1    edgecoresw1             Edgecore switch                                         8C:EA:1B:12:CA:40
   Switch discovered: edgecoresw1

Once SNMP on the ONIE switch is enabled, the ONIE switch can be discovered with "snmp" method: :: 

   ~: switchdiscover --range 192.168.23.1-10 -s snmp
   Discovering switches using snmpwalk for 192.168.23.1-10 ....
   ip              name           vendor                                                                                  mac
   ------------    ------------   ------------                                                                            ------------
   192.168.23.1    edgecoresw1    Linux edgecoresw1 4.1.0-cl-2-iproc #1 SMP Debian 4.1.25-1+cl3u4 (2016-08-13) armv7l     8c:ea:1b:12:ca:40
   Switch discovered: edgecoresw1


Switch Management
-----------------

File Dispatch 
~~~~~~~~~~~~~

The files can be dispatched to ONIE switches with ``xdcp`` ::
   
   xdcp edgecoresw1 <path of file to dispatch> <destination path of the file on switch>

Refer to :doc:`xdcp manpage </guides/admin-guides/references/man1/xdcp.1>` for details. 

Remote Commands
~~~~~~~~~~~~~~~

Commands can be run on ONIE switches remotely  with ``xdsh`` ::

   xdsh edgecoresw1 <remote commands>

Refer to :doc:`xdsh manpage </guides/admin-guides/references/man1/xdsh.1>` for details.

Run scripts remotely
~~~~~~~~~~~~~~~~~~~~

The scripts under "/install/postscripts" can be run on ONIE switches with ``updatenode -P`` ::

   updatenode edgecoresw1 -P <script name> 

Refer to :doc:`updatenode manpage </guides/admin-guides/references/man1/updatenode.1>` for details.


