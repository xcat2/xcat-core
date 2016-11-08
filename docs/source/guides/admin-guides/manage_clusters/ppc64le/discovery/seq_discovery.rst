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

In order to do BMC configuration during the discovery process, set ``runcmd=bmcsetup``. ::

    chdef cn1 chain="runcmd=bmcsetup"

Set the target `osimage` into the chain table to automatically provision the operating system after the node discovery is complete. ::

    chdef cn1 -p chain="osimage=<osimage_name>"

For more information about chain, refer to :doc:`Chain <../../../../../advanced/chain/index>`

Initialize the discovery process
````````````````````````````````

Specify the predefined nodes to the nodediscoverstart command to initialize the discovery process::

    nodediscoverstart noderange=cn1

See "nodediscoverstart man page<TBD>" for more details.

Display information about the discovery process
```````````````````````````````````````````````

There are additional nodediscover commands you can run during the discovery process. See their man pages for more details.


Verify the status of discovery::
    
    nodediscoverstatus

Show the nodes that have been discovered so far::
    
    nodediscoverls -t seq -l

Stop the current sequential discovery process::
    
    nodediscoverstop

Note: The sequential discovery process will be stopped automatically when all of the node names in the node pool are used up. 

Start discovery process
-----------------------

To start the discovery process, the system administrator needs to power on the servers one by one manually. Then the hardware discovery process will start automatically.

.. include:: standard_cn_definition.rst
