Set attributes in the ``networks`` table 
========================================

#. Display the network settings defined in the xCAT ``networks`` table using: ``tabdump networks`` ::
  
       #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,
       dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,
       comments,disable
       "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0","10.0.0.101",,"10.4.27.5",,,,,,,,,,,,,

   A default network is created for the detected primary network using the same netmask and gateway.  There may be additional network entries in the table for each network present on the management node where xCAT is installed.

#. To define additional networks, use one of the following options:

   *  [**Recommended**] Use ``mkdef`` to create/update an entry into ``networks`` table.

      To create a network entry for 192.168.X.X/16 with a gateway of 192.168.1.254: ::

          mkdef -t network -o net1 net=192.168.0.0 mask=255.255.0.0 gateway=192.168.1.254

   *  Use the ``tabedit`` command to modify the networks table directly in an editor: ::

          tabedit networks

   *  Use the ``makenetworks`` command to automatically generate a entry in the ``networks`` table:  ::

          makenetworks

#. Verify the network statements 

   **Domain** and **nameserver** attributes must be configured in the ``networks`` table or in the ``site`` table for xCAT to function properly.



Initialize DHCP services
------------------------

Configure DHCP to listen on different network interfaces [**Optional**]

   The default behavior of xCAT is to configure DHCP to listen on all interfaces defined in the ``networks`` table.  

   The ``dhcpinterfaces`` keyword in the ``site`` table allows administrators to limit the interfaces that DHCP will listen over.  If the management node has 4 interfaces, (eth0, eth1, eth2, and eth3), and you want DHCP to listen only on "eth1" and "eth3", set ``dhcpinterfaces`` using: ::

      chdef -t site dhcpinterfaces="eth1,eth3"

   To set "eth1" and "eth3" on the management node and "bond0" on all nodes in the nodegroup="service", set ``dhcpinterfaces`` using: ::

      chdef -t site dhcpinterfaces="xcatmn|eth1,eth3;service|bond0"

**noboot**
``````````
   For the *IBM OpenPOWER S822LC for HPC ("Minsky")* nodes, the BMC and compute "eth0" share the left-side integrated ethernet port and compute "eth1" is the right-side integrated ethernet port.  For these servers, it is recommended to use two physical cables allowing the BMC port to be dedicated and "eth1" used by the OS.  When an open range is configured on the two networks, the xCAT Genesis kernel will be sent to the BMC interface and causes problems during hardware discovery.  To support this scenario, on the xCAT management node, if "eth1" is connected to the BMC network and "eth3" is connected to the compute network, disable genesis boot for the BMC network by setting ``:noboot`` in ``dhcpinterfaces`` using: ::
     
      chdef -t site dhcpinterfaces="eth1:noboot,eth3" 

      # run the mknb command to remove the genesis 
      # configuration file for the specified network
      mknb ppc64

   
For more information, see ``dhcpinterfaces`` keyword in the :doc:`site </guides/admin-guides/references/man5/site.5>` table.


After making any DHCP changes, create a new DHCP configuration file with the networks defined using the ``makedhcp`` command. ::

       makedhcp -n

