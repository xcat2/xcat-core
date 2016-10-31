Network Planning
================

For a cluster, several networks are necessary to enable the cluster management and production.

* **Management network**

  This network is used by the management node to install and manage the OS of the nodes. The MN and in-band NIC of the nodes are connected to this network. If you have a large cluster with service nodes, sometimes this network is segregated into separate VLANs for each service node.

  Following network services need be set up in this network to supply the OS deployment, application install/configuration service.

  * DNS(Domain Name Service)

    The dns server, usually the management node or service node, provides the domain name service for the entire cluster.

  * HTTP(HyperText Transfer Protocol)

    The http server,usually the management node or service node, acts as the download server for the initrd and kernel, the configuration file for the installer and repository for the online installation.

  * DHCP(Dynamic Host Configuration Protocol)

    The dhcp server, usually the management node or service node, provides the dhcp service for the entire cluster.

  * TFTP(Trivial File Transfer Protocol)

    The tftp server, usually the management node or service node, acts as the download server for bootloader binaries, bootloader configuration file, initrd and kernel.

  * NFS(Network File System)

    The NFS server, usually the management node or service node, provides the file system sharing between the management node and service node, or persistent file system support for the stateless node.

  * NTP(Network Time Protocol)

    The NTP server, usually the management node or service node, provide the network time service for the entire cluster.

* **Service network**

  This network is used by the management node to control the nodes out of band via the SP like BMC, FSP. If the BMCs are configured in shared mode [1]_, then this network can be combined with the management network.

* **Application network**

  This network is used by the applications on the compute nodes. Usually an IB network for HPC cluster.

* **Site (Public) network**
  This network is used to access the management node and sometimes for the compute nodes to provide services to the site.

From the system management perspective, the **Management network** and **Service network** are necessary to perform the hardware control and OS deployment.

**xCAT Network Planning for a New Cluster:** 

.. toctree::
   :maxdepth: 2

   xcat_net_planning.rst


.. [1] shared mode: In "Shared" mode, the BMC network interface and the in-band network interface will share the same network port.
