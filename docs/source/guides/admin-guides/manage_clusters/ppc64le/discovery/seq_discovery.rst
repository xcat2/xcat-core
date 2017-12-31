.. include:: ../../common/discover/seq_discovery.rst

When the physical location of the server is not so important, sequential-based hardware discovery can be used to simplify the discovery work. The idea is: provided a node pool, each node in the pool will be assigned an IP address for host and an IP address for FSP/BMC, then the first physical server discovery request will be matched to the first free node in the node pool, and IP addresses for host and FSP/BMC will be assigned to that physical server.

.. include:: schedule_environment.rst
.. include:: config_environment.rst

Prepare node pool
-----------------

To prepare the node pool, shall predefine nodes first, then initialize the discovery process with the predefined nodes.

Predefine nodes
```````````````

Predefine a group of nodes with desired IP address for host and IP address for FSP/BMC::

    nodeadd cn1 groups=powerLE,all
    chdef cn1 mgt=ipmi cons=ipmi ip=10.0.101.1 bmc=50.0.101.1 netboot=petitboot installnic=mac primarynic=mac

**[Optional]** If more configuration planed to be done on BMC, the following command is also needed. ::

    chdef cn1 bmcvlantag=<vlanid>                 # tag VLAN ID for BMC
    chdef cn1 bmcusername=<desired_username>
    chdef cn1 bmcpassword=<desired_password>

In order to do BMC configuration during the discovery process, set ``runcmd=bmcsetup``. ::

    chdef cn1 chain="runcmd=bmcsetup"

**[Optional]** More operation plan to do after hardware disocvery is done, ``ondiscover`` option can be used.

   For example, configure console, copy SSH key for **OpenBMC**, then disable ``powersupplyredundancy`` ::

       chdef cn01 -p chain="ondiscover=makegocons|rspconfig:sshcfg|rspconfig:powersupplyredundancy=disabled"

   **Note**: ``|`` is used to split commands, and ``:`` is used to split command with its option.

Set the target `osimage` into the chain table to automatically provision the operating system after the node discovery is complete. ::

    chdef cn1 -p chain="osimage=<osimage_name>"

For more information about chain, refer to :doc:`Chain <../../../../../advanced/chain/index>`

Initialize the discovery process
````````````````````````````````

Specify the predefined nodes to the `nodediscoverstart` command to initialize the discovery process::

    nodediscoverstart noderange=cn1

See :doc:`nodediscoverstart </guides/admin-guides/references/man1/nodediscoverstart.1>` for more information.

Display information about the discovery process
```````````````````````````````````````````````

There are additional `nodediscover*` commands you can run during the discovery process. See the man pages for more details.


Verify the status of discovery using :doc:`nodediscoverstatus </guides/admin-guides/references/man1/nodediscoverstatus.1>`::

    nodediscoverstatus

Show the nodes that have been discovered using :doc:`nodediscoverls </guides/admin-guides/references/man1/nodediscoverls.1>`::

    nodediscoverls -t seq -l

Stop the current sequential discovery process using: :doc:`nodediscoverstop </guides/admin-guides/references/man1/nodediscoverstop.1>`::

    nodediscoverstop


**Note:** The sequential discovery process will stop automatically when all of the node names in the pool are consumed.

Start discovery process
-----------------------

To start the discovery process, the system administrator needs to power on the servers one by one manually. Then the hardware discovery process will start automatically.

Verify Node Definition
----------------------

After discovery of the node, properties of the server will be added to the xCAT node definition.

Display the node definition and verify that the MAC address has been populated.
