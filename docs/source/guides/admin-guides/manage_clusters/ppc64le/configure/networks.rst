Set attributes in the ``networks`` table 
========================================

#. Display the network settings defined in the xCAT ``networks`` table using: ``tabdump networks`` ::
  
       #netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,
       dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,
       comments,disable
       "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0","10.0.0.101",,"10.4.27.5",,,,,,,,,,,,

   A default network is created for the detected primary network using the same netmask and gateway.  There may be additional network entries in the table for each network present on the management node where xCAT is installed.

#. To define additional networks, use one of the following options:

   *  Use ``mkdef`` to create/update an entry into ``networks`` table. (**Recommended**)

      To create a network entry for 192.168.X.X/16 with a gateway of 192.168.1.254: ::

          mkdef -t network -o net1 net=192.168.0.0 mask=255.255.0.0 gateway=192.168.1.254

   *  Use the ``tabedit`` command to modify the networks table directly in an editor: ``tabedit networks`` 

   *  Use the ``makenetworks`` command to automatically generate a entry in the ``networks`` table

#. Verify the network statements 

   **Domain** and **nameserver** attributes must be configured in the ``networks`` table or in the ``site`` table for xCAT to function properly.



Initialize DHCP services
------------------------

#. Configure DHCP to listen on different network interfaces (**Optional**)

   xCAT allows specifying different network intercaces thateDHCP can listen on for different nodes or node groups.  If this is not needed, go to the next step.  To set dhcpinterfaces :: 

       chdef -t site dhcpinterfaces='xcatmn|eth1,eth2;service|bond0'

   For more information, see ``dhcpinterfaces`` keyword in the :doc:`site </guides/admin-guides/references/man5/site.5>` table.


#. Create a new DHCP configuration file with the networks defined using the ``makedhcp`` command. ::

       makedhcp -n

