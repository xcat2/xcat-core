Set attributes in the ``networks`` table 
========================================

#. Display the network settings defined in the xCAT ``networks`` table using: ``tabdump networks`` ::
  
       #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,
       dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,
       comments,disable
       "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0","10.0.0.101",,"10.4.27.5",,,,,,,,,,,,,

   A default network is created for the detected primary network using the same netmask and gateway.  There may be additional network entries in the table for each network present on the management node where xCAT is installed.

#. To define additional networks, use one of the following options:

   *  (**Recommended**) Use ``mkdef`` to create/update an entry into ``networks`` table.

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

#. Configure DHCP to listen on different network interfaces (**Optional**)

   The ``dhcpinterfaces`` keyword allows users to specify or limit the DHCP to listen over certain network interfaces.

   If the management node has 4 interfaces, (eth0, eth1, eth2, and eth3), and you want DHCP to listen only on "eth1" and "eth3", set ``dhcpinterfaces`` with: ::

      chdef -t site dhcpinterfaces="eth1,eth3"

   To set "eth1" and "eth3" on the management node, and "bond0" on all the nodes in the "service" nodegroup, set ``dhcpinterfaces`` with: ::

      chdef -t site dhcpinterfaces="xcatmn|eth1,eth3;service|bond0"

   [**noboot**]: For the IBM OpenPower S822LC for HPC ("Minsky") nodes, the BMC and "eth0" on the compute side shares the same physical ethernet port.  However, it is recommended to allow the BMC to be dedicated and to use "eth1" for the compute node.   When an open range is configured on the two networks, the xCAT Genesis Kernel will be sent to the BMC interface and will cause problems with discovery.  In this scenario, if "eth1" is the BMC network and "eth3" is the compute network, disabled genesis by setting ``:noboot`` in ``dhcpinterfaces`` with: ::
     
      chdef -t site dhcpinterfaces="eth1:noboot,eth3" 

   
   For more information, see ``dhcpinterfaces`` keyword in the :doc:`site </guides/admin-guides/references/man5/site.5>` table.

#. Create a new DHCP configuration file with the networks defined using the ``makedhcp`` command. ::

       makedhcp -n

