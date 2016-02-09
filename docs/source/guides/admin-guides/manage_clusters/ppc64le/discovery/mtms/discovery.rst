Discover and Define Servers
===========================

When the IPMI-based server is connected to power, the BMC automatically boots up and tries to a DHCP IP address.  Once the BMC gets an IP address, xCAT can discover the BMC and obtain some basic information.  Use the :doc:`bmcdiscover </guides/admin-guides/references/man1/bmcdiscover.1>` command to scan the network for BMCs.

#. Discover the BMCs over a network range. ::

       bmcdiscover --range 50.0.100.1-100 -t -z 

   The output should be similar to:  ::

       node-8247-22l-10112ca:
        objtype=node
        groups=all
        bmc=50.0.100.1
        cons=ipmi
        mgt=ipmi
        mtm=8247-22L
        serial=10112CA
        nodetype=mp
        hwtype=bmc

   By default, ``bmcdiscover`` will use the username/password for the "ipmi" key in the xCAT ``passwd`` table.  You can specify a different username or password with command line optjons to ``bmcdiscover``. 

#. If the output looks good, run the command again using the ``-w`` option to write to the xCAT database and redirect the output to a file in order to create the **predefined** node stanzas: ::

      bmcdiscover --range 50.0.100.1-100 -t -z -w > predefined_bmc.stanza

#. The discovered node stanza is now in the xCAT databased.  Edit the ``predefined_bmc.stanza`` file and modify the following: 

    #. Rename the ``node-8247-22l-10112ca`` to the intended hostname for the compute node

    #. Remove the ``nodetype`` and ``hwtype`` attributes for the node stanza

   The resulting predefined definition should be similar to: ::

       cn1:
        objtype=node
        groups=all
        bmc=50.0.100.1
        cons=ipmi
        mgt=ipmi
        mtm=8247-22L
        serial=10112CA

  
#. Define the predefined node to xCAT: [#]_ ::

       cat predefined_bmc.stanza | mkdef -z 



#. Modify the predefined node using xCAT commands

   #. Set the IP address for the compute node: ::

       chdef cn1 ip=10.0.101.1

   #. Set the BMC IP address to a different value: ::

       chdef cn1 bmc=50.0.101.1

   #. Set the chain table attribute to do BMC setup/discovery: ::

       chdef cn1 chain="runcmd=bmcsetup"


#. Add the node information to ``/etc/hosts`` and DNS: ::

       makehosts cn1
       makedns -n 


#. [**Optional**] To monitor the node discovery process, configure conserver for the **discovered** nodes: ::

       makeconservercf node-8247-22l-10112ca
       rcons node-8247-22l-10112ca

#. Start the discovery process by booting the **discovered** node definition: ::

       rsetboot node-8247-22l-10112ca net
       rpower node-8247-22l-10112ca on

#. The discovery process should complete and update the status for the **predefined** node and update the status to "bmcready": ::

       lsdef cn1 | grep status

   Displaying the node attributes should show more attributes discoverd for the node, necessary for xCAT to do OS deployment. 


.. [#] The changes made in the next step can be made directly into the ``predefined_bmc.stanza`` before importing to xCAT.
