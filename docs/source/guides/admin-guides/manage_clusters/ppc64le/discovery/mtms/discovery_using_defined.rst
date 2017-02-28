Set static BMC IP using different IP address (recommended) 
==========================================================

The following example outlines the MTMS based hardware discovery for a single IPMI-based compute node.  

+------------------------------+------------+
| Compute Node Information     | Value      |
+==============================+============+
| Model Type                   | 8247-22l   |
+------------------------------+------------+
| Serial Number                | 10112CA    |
+------------------------------+------------+
| Hostname                     | cn01       |
+------------------------------+------------+
| IP address                   | 10.1.2.1   |
+------------------------------+------------+

The BMC IP address is obtained by the open range dhcp server and the plan in this scenario is to change the IP address for the BMC to a static IP address in a different subnet than the open range addresses.  The static IP address in this example is in the same subnet as the open range to simplify the networking configuration on the xCAT management node.

+------------------------------+------------+
| BMC Information              | Value      |
+==============================+============+
| IP address - dhcp            | 172.30.0.1 |
+------------------------------+------------+
| IP address - static          | 172.20.2.1 |
+------------------------------+------------+

#. Detect the BMCs and add the node definitions into xCAT.

   Use the :doc:`bmcdiscover </guides/admin-guides/references/man1/bmcdiscover.1>` command to discover the BMCs responding over an IP range and write the output into the xCAT database.  This discovered BMC node is used to control the physical server during hardware discovery and will be deleted after the correct server node object is matched to a pre-defined node.  You **must** use the ``-w`` option to write the output into the xCAT database. 

   To discover the BMC with an IP address range of 50.0.100.1-100: ::

      bmcdiscover --range 50.0.100.1-100 -z -w

   The discovered nodes will be written to xCAT database.  The discovered BMC nodes are in the form **node-model_type-serial**.   To view the discovered nodes: ::

      lsdef /node-.*

   **Note:** The ``bmcdiscover`` command will use the username/password from the ``passwd`` table corresponding to ``key=ipmi``.  To overwrite with a different username/password use the ``-u`` and ``-p`` option to ``bmcdiscover``.


#. **Pre-define** the compute nodes:

   Use the ``bmcdiscover`` command to help discover the nodes over an IP range and easily create a starting file to define the compute nodes into xCAT.

   To discover the compute nodes for the BMCs with an IP address of 172.30.0.1, use the command: ::

      bmcdiscover --range 172.30.0.1 -z > predefined.stanzas

   The discovered nodes have the naming convention:  node-<*model-type*>-<*serial-number*> ::

      # cat predefined.stanzas
      node-8247-22l-10112ca:
        objtype=node
        groups=all
        bmc=172.30.0.1
        cons=ipmi
        mgt=ipmi
        mtm=8247-22L
        serial=10112CA


#. Edit the ``predefined.stanzas`` file and change the discovered nodes to the intended ``hostname`` and ``IP address``. 

    #. Edit the ``predefined.stanzas`` file: ::

         vi predefined.stanzas

    #. Rename the discovered object names to their intended compute node hostnames based on the MTMS mapping: ::

         node-8247-22l-10112ca ==> cn01

    #. Add a ``ip`` attribute and give it the compute node IP address: ::

          ip=10.1.2.1

    #. Remove ``nodetype`` and ``hwtype`` if defined in the ``predefined.stanza``.

    #. Repeat for additional nodes in the ``predefined.stanza`` file based on the MTMS mapping.


    In this example, the ``predefined.stanzas`` file now looks like the following: ::

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


#. Set the chain table to run the ``bmcsetup`` script, this will set the BMC IP to static. ::

       chdef cn01 chain="runcmd=bmcsetup"

#. Set the target `osimage` into the chain table to automatically provision the operating system after the node discovery is complete. ::

       chdef cn01 -p chain="osimage=<osimage_name>"

#. Change the BMC IP address 

   Set the BMC IP address to a different value for the **predefined** compute node definitions.  

   To change the dhcp obtained IP address of 172.30.0.1 to a static IP address of 172.20.2.1, run the following command: ::

       chdef cn01 bmc=172.20.2.1 

#. Define the compute nodes into xCAT: ::

       cat predefined.stanzas | mkdef -z 

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
