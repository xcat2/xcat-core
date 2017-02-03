Installation and Configuration
==============================

Cumulus OS Installtion
----------------------

The following assumes that the physical switches have power and have obtained a DHCP IP address from the xCAT open range.  

xCAT provides support for detecting and installing the Cumulus Linux OS into ONIE enabled switches by utilizing DHCP to detect "**onie_vendor**" from the ``vendor-class-identifier`` string and then sends it the Cumulus Linux OS.  

#. Create a pre-defined switch definition for the ONIE switch using the ``onieswitch`` template.

   The mac address of the switch management port is required for xCAT to configure the DHCP information and send over the OS to install on the switch. 

   For smaller clusters, if you know the mac address of the management port on the switch, simply create the pre-defined switch defintion providing the mac address: ::

       mkdef switch01 --template onieswitch arch=armv71 \
           ip=192.168.1.1 mac="aa:bb:cc:dd:ee:ff"

    For large clusters, xCAT's :doc:`switchdiscover </guides/admin-guides/references/man1/switchdiscover.1>` command can be used to discover the mac address and fill in the predefined switch definitions based on the switch/switchport mapping.  

    #. Define the switch objects ::

         mkdef switch01 --template onieswitch arch=armv71 \
             ip=192.168.1.1 switch=coresw1 switchport=1
         mkdef switch02 --template onieswitch arch=armv71 \
             ip=192.168.2.1 switch=coresw1 switchport=2
         mkdef switch03 --template onieswitch arch=armv71 \
             ip=192.168.3.1 switch=coresw1 switchport=3
         mkdef switch04 --template onieswitch arch=armv71 \
             ip=192.168.4.1 switch=coresw1 switchport=4
         ... 
  
    #. Leverage ``switchdiscover`` over the DHCP range to detect the MAC addrees and write them into the predefined swtiches above. ::

         switchdiscover --range <IP range>


#. Set the ``provmethod`` of the target switch to the Cumulus Linux install image:  ::

    chdef <switch> provmethod="/install/custom/sw_os/cumulus/cumulus-linux-3.1.0-bcm-armel.bin"

#. Run ``makedhcp`` to prepare the DHCP/BOOTP lease information for the switch: ::

    makedhcp -a <switch> 

At this point, the DHCPREQUEST from the switch should get the Cumulus Linux OS as a response and begin the installation.  

Normal Installation time is around 1 hour. 

Configure xCAT Remote Commands
------------------------------

After Cumulus Linux OS is installed, a default user ``cumulus`` will be created.  The default password is: ``CumulusLinux!``.

To ease in the management of the switch, xCAT provides a script to help configure password-less ssh as the ``root`` user.  This script sends over the xCAT ssh keys so that the xCAT remote commands (``xdsh``, ``xdcp``, etc) can be run against the ONIE switches.  

Execute the following to sync the xCAT keys to the switch: ::

    /opt/xcat/share/xcat/scripts/configonie --switches <switch> --ssh 


Activate the License
--------------------

After Cumulus Linux OS is installed onto the ONIE switch, only the serial port console and the management ethernet port is enabled.  To activate the rest of the switch ports, the license file needs to be installed onto the switch. 

#. Copy the license file to the switch: ::

    xdcp <switch> /install/custom/sw_os/cumulus/licensefile.txt /root/

#. Activate the license: ::

    xdsh <switch> "/usr/cumulus/bin/cl-license -i /root/licensefile.txt"

#. Verify that the license file is successfully installed: ::

    xdsh <switch> /usr/cumulus/bin/cl-license

  Output should be similar to: ``<switch> xxx@xx.com|xxxxxxxxxxxxxxx``

#. Reboot the switch to apply the license file: ::

    xdsh <switch> reboot


Enable SNMP (optional)
----------------------

To enable ``snmpd``, execute the ``enablesnmp`` postscript on the switch: ``updatenode <switch> -P enablesnmp``.  


