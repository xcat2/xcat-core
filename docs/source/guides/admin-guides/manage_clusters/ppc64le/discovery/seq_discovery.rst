.. include:: ../../common/discover/seq_discovery.rst

When the physical location of the server is not so important, sequential base hardware discovery can be used to simplify the discovery work. The idea is: providing a node pool, each node in the pool will be assigned an IP address for host and an IP address for FSP/BMC, then match first came physical server discovery request to the first free node in the node pool and configure the assigned IP address for host and FSP/BMC onto that pysical server.

.. include:: schedule_environment.rst
.. include:: config_environment.rst

Prepare node pool
-----------------

To prepare the node pool, shall predefine nodes first, then initialize the discovery process with the predefined nodes. 

Predefine nodes
^^^^^^^^^^^^^^^

Predefine a group of node with desired IP address for host and IP address for FSP/BMC::

    #nodeadd cn1 groups=pkvm,all
    #chdef cn1 mgt=ipmi cons=ipmi ip=10.1.101.1 bmc=10.2.101.1 netboot=petitboot installnic=mac primarynic=mac
 
Initialize the discovery process
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Specify the predefined nodes to the nodediscoverstart command to initialize the discovery process::

#nodediscoverstart noderange=cn1

Pls see "nodediscoverstart man page<TBD>" for more details.

Display information about the discovery process
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

There are additional nodediscover commands you can run during the discovery process. See their man pages for more details.


Verify the status of discovery::
    
    nodediscoverstatus

Show the nodes that have been discovered so far::
    
    nodediscoverls -t seq -l

Stop the current sequential discovery process::
    
    nodediscoverstop

Note: The sequential discovery process will be stopped automatically when all of the node names in the node pool are used up. 

.. include:: pbmc_discovery.rst
.. include:: standard_cn_definition.rst
