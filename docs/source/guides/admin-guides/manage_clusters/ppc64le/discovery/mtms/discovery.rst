Discovery
=========

When the IPMI-based servers are connected to power, the default setting from manuafacturing is DHCP mode and the BMCs will obtain a IP address from an open range DHCP server on your network.  (xCAT can start an open range on the DHCP server by setting the ``dynamicrange`` attribute in the networks table) 

When the BMCs have an IP address and is pingable from the xCAT management node, administrators can discover the BMCs using the xCAT :doc:`bmcdiscover </guides/admin-guides/references/man1/bmcdiscover.1>` command and obtain basic information to start the hardware discovery process.  When hardware discovery is running, xCAT uses the genesis kernel to discover attributes of the compute node and populate the node attributes so xCAT can then manage the node. 

The following example outlines the MTMS based hardware discovery for a single IPMI-based compute node. 

+-------------------------+------------+
| Environment             | Value      |
+=========================+============+
| Compute Node Model Type | 8247-22l   |
+-------------------------+------------+
| Compute Node Serial Num | 10112CA    |
+-------------------------+------------+
| Compute Node Hostname   | cn01       |
+-------------------------+------------+
| Compute Node IP address | 10.1.2.1   |
+-------------------------+------------+
| BMC DHCP IP address     | 172.30.0.1 |
+-------------------------+------------+
| BMC STATIC IP address   | 172.20.0.1 |
+-------------------------+------------+

#. Gather the **predefined** nodes

   Using the ``bmcdiscover`` command, discover the nodes over an IP range and save the output to a file to use as a base for creating the **predefined** compute nodes.  

   To discover the BMC with an IP address of 172.30.0.1, use the command: ::

      bmcdiscover --range 172.30.0.1 -z > predefined.stanzas

   The discovered nodes has the naming convention:  node-<*model-type*>-<*serial-number*> ::

      # cat predefined.stanzas
      node-8247-22l-10112ca:
        objtype=node
        groups=all
        bmc=172.30.0.1
        cons=ipmi
        mgt=ipmi
        mtm=8247-22L
        serial=10112CA


#. Gather the **discovered** nodes

   Using the ``bmcdiscover`` command again to discover the nodes over the IP range, but use the ``-t`` option to get machine type information and the ``-w`` option to automatically write the output to the xCAT database. 

   To discover the BMC with an IP address of 172.30.0.1, use the command: ::

      bmcdiscover --range 172.30.0.1 -t -z -w 

   The discovered nodes will be written to xCAT database: ::

      # lsdef node-8247-22l-10112ca
      Object name: node-8247-22l-10112ca
          bmc=172.30.0.1
          cons=ipmi
          groups=all
          hwtype=bmc
          mgt=ipmi
          mtm=8247-22L
          nodetype=mp
          postbootscripts=otherpkgs
          postscripts=syslog,remoteshell,syncfiles
          serial=10112CA


#. Edit the **predefined** nodes and set their intended ``hostname`` and ``IP adress``

    #. Edit the file saved from the above step. ::

         vi predefined.stanzas

    #. Rename the object names to their intended compute node hostnames. ::

         node-8247-22l-10112ca ==> cn01

    #. Set the ``ip=`` attribute for the compute node IP address. ::

          ip=10.1.2.1

    #. Repeat for additional nodes in the predefined.stanza file based on the MTMS mapping.


    In this example, our **predefined.stanzas** file now looks like the following: ::

        # cat predefined.stanzas
        cn01:
          objtype=node
          groups=all
          bmc=172.30.0.1
          cons=ipmi
          mgt=ipmi
          mtm=8247-22L
          serial=10112CA
          ip=10.1.2.1 


#. Define the **predefined node** to xCAT: ::

       cat predefined.stanzas | mkdef -z 

#. **[Optional]** Change the BMC IP address from DHCP to STATIC

   Some sites would prefer to configure the BMCs to use static IP addresses to avoid issues when DHCP leases expire.  xCAT provides a way for the administrator to modify theDHCP IP address to a static IP address during the hardware discovery process using the xCAT chain concept. 

   Set the BMC IP address to a different value for the **predefined** compute node definitions.  

   To change the DHCP IP address of 172.30.0.1 to a STATIC IP address of 172.**20**.0.1, run the following command: ::

       chdef cn01 bmc=172.20.0.1 chain="rumcmd=bmcsetup"


#. Add the compute node IP information to ``/etc/hosts``: ::

       makehosts cn01

#. Refresh the DNS configuration for the new hosts: ::

       makedns -n 

#. **[Optional]**  Monitor the node discovery process using rcons

   Configure the conserver for the **discovered** node to watch the discovery process using ``rcons``::

       makeconservercf node-8247-22l-10112ca

   In another terminal window, open the remote console: ::

       rcons node-8247-22l-10112ca

#. Start the discovery process by booting the **discovered** node definition: ::

       rsetboot node-8247-22l-10112ca net
       rpower node-8247-22l-10112ca on

#. The discovery process will network boot the machine into the diskless xCAT genesis kernel and perform the discovery process. When the discovery process is complete, doing ``lsdef`` on the compute nodes should show discovered attributes for the machine.  The important ``mac`` information should be discovered, which is necessary for xCAT to perform OS provisioning. 
