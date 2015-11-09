Architecture
============

The following diagram shows the basic structure of xCAT:

.. image:: Xcat-arch.png

xCAT Management Node (xCAT Mgmt Node):
  The server which installed xCAT and is used to perform the system management for the whole cluster. Generally, the database is installed in this server to store the Definition of Compute Node; The network services like dhcpd, tftpd, httpd are enabled on this server for OS deployment.

Service Node:
  An slave server of **Mgmt Node** to take over the system management work for part of nodes in the cluster. **Service Node** has all the functions of **Mgmt Node**, but generally it only works under **Mgmt Node**'s instruction.

  The **Service Node** is necessary only for large cluster that **Mgmt Node** cannot handle all the nodes because of the limitation of CPU, Memory or Network Bandwidth of **Mgmt Node**.

Compute Node (Target Node):
  The target node or workload nodes in the cluster which are the targets servers of the xCAT to manage for customer.

dhcpd, tftpd, httpd:
  The network services that are used to perform the OS deployment. xCAT handles these network services automatically, user does not need to configure the network services by themselves.

SP (Service Processor):
  A hardware Module imbedded in the hardware server which is used to perform the out-of-band hardware control. e.g. the IMM or FSP

Management network:
  It's used by the **Mgmt Node** or **Service Node** to install and manage the OS of the nodes. The MN and in-band NIC of the nodes are connected to this network. If you have a large cluster with service nodes, sometimes this network is segregated into separate VLANs for each service node. See TODO [Setting_Up_a_Linux_Hierarchical_Cluster] for details.

Service network:
  It's used by the **Mgmt Node** or **Service Node** to control the nodes out of band via the SP. If the SPs are configured in shared mode (NIC of SP can be used to access both SP and server host), then this network can be combined with the management network.

Application network:
  It's used by the applications on the **Compute Node** to communicate among each other. Usually it's an IB network.

Site (Public) network:
  It's used to by user to access the management node and sometimes for the compute nodes to provide services to the site.

Rest API:
  The rest api interface of xCAT which can be used by the third-party application to integrate with xCAT.
