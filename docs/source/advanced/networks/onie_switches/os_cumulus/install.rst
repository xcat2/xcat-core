Installation and Configuration
==============================

Cumulus OS Installtion
----------------------

**Note:** *The following assumes that the physical switches have power and have obtained a DHCP IP address from the xCAT open range.*

xCAT provides support for detecting and installing the Cumulus Linux OS into ONIE enabled switches by utilizing DHCP to detect "**onie_vendor**" from the ``vendor-class-identifier`` string and then send it the Cumulus Linux OS installer.

#. Create a pre-defined switch definition for the ONIE switch using the ``onieswitch`` template.

   The mac address of the switch management port is required for xCAT to configure the DHCP information and send over the OS to install on the switch. 

   **[small clusters]** If you know the mac address of the management port on the switch, create the pre-defined switch defintion providing the mac address. ::

       mkdef frame01sw1 --template onieswitch arch=armv71 \
           ip=192.168.1.1 mac="aa:bb:cc:dd:ee:ff"

   **[large clusters]** xCAT's :doc:`switchdiscover </guides/admin-guides/references/man1/switchdiscover.1>` command can be used to discover the mac address and fill in the predefined switch definitions based on the switch/switchport mapping.  


    #. Define all the switch objects providing the switch/switchport mapping: ::

         mkdef frame01sw1 --template onieswitch arch=armv71 \
             ip=192.168.1.1 switch=coresw1 switchport=1
         mkdef frame02sw1 --template onieswitch arch=armv71 \
             ip=192.168.2.1 switch=coresw1 switchport=2
         mkdef frame03sw1 --template onieswitch arch=armv71 \
             ip=192.168.3.1 switch=coresw1 switchport=3
         mkdef frame04sw1 --template onieswitch arch=armv71 \
             ip=192.168.4.1 switch=coresw1 switchport=4
         ... 
  
    #. Leverage ``switchdiscover`` over the DHCP range to automatically detect the MAC address and write them into the predefined swtiches above. ::

         switchdiscover --range <IP range>


#. Set the ``provmethod`` attribute of the target switch(es) to the Cumulus Linux install image:  ::

    chdef frame[01-04]sw1 \
      provmethod="/install/custom/sw_os/cumulus/cumulus-linux-3.1.0-bcm-armel.bin"

#. Run ``makedhcp`` to prepare the DHCP/BOOTP lease information for the switch: ::

    makedhcp -a frame[01-04]sw1

   Executing the ``makedhcp`` command will kick off the network install of the ONIE enabled switch.  If there is no OS pre-loaded on the switch, the switch continues to send a DHCPREQUEST out to the network.   After ``makedhcp`` is run against the switch, an entry is added to the leases file that will respond to the request with the Cumulus Linux installer file. ::

       host frame1sw1 {
         dynamic;
         hardware ethernet 8c:ea:1b:12:ca:40;
         fixed-address 192.168.3.200;
               supersede server.ddns-hostname = "frame1sw1";
               supersede host-name = "frame1sw1";
               if substring (option vendor-class-identifier, 0, 11) = "onie_vendor" {
                 supersede www-server = "http://192.168.27.1/install/custom/sw_os/cumulus/cumulus-linux-3.1.0-bcm-armel.bin";
               }
       }

   *Typical installation time is around 1 hour*


Configure xCAT Remote Commands
------------------------------

After Cumulus Linux OS is installed, a default user ``cumulus`` will be created with default password: ``CumulusLinux!``.

To ease in the management of the switch, xCAT provides a script to help configure password-less ssh as the ``root`` user.  This script sends over the xCAT ssh keys so that the xCAT remote commands (``xdsh``, ``xdcp``, etc) can be run against the ONIE switches.  

Execute the following to sync the xCAT keys to the switch: ::

    /opt/xcat/share/xcat/scripts/configonie --switches frame01sw1 --ssh 

Validate the ssh keys are correctly configured by running a ``xdsh`` command: ::

    xdsh frame01sw1 uptime


Activate the License
--------------------

After Cumulus Linux OS is installed onto the ONIE switch, only the serial port console and the management ethernet port is enabled.  To activate the rest of the switch ports, the license file needs to be installed onto the switch. 

#. Copy the license file to the switch: ::

      xdcp frame01sw1 /install/custom/sw_os/cumulus/licensefile.txt /root/

#. Activate the license: ::

      xdsh frame01sw1 "/usr/cumulus/bin/cl-license -i /root/licensefile.txt"

#. Verify that the license file is successfully installed: ::

      xdsh frame01sw1 /usr/cumulus/bin/cl-license

   Output should be similar to: ``frame01sw1 xxx@xx.com|xxxxxxxxxxxxxxx``

#. Reboot the switch to apply the license file: ::

      xdsh frame01sw1 reboot


Enable SNMP (optional)
----------------------

In order to utilize ``xcatprobe switch_macmap``, snmp needs to be enabled.  To enable, run the ``enablesnmp`` postscript on the switch: ::

    updatenode frame01sw1 -P enablesnmp


