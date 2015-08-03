========
Overview
========


The xCAT management node plays an important role in the cluster, if the management node is down for whatever reason, the administrators will lose the management capability for the whole cluster, until the management node is back up and running. In some configuration, like the Linux nfs-based statelite in a non-hierarchy cluster, the compute nodes may not be able to run at all without the management node. So, it is important to consider the high availability for the management node. 

The goal of the HAMN(High Availability Management Node) configuration is, when the primary xCAT management node fails, the standby management node can take over the role of the management node, either through automatic failover or through manual procedure performed by the administrator, and thus avoid long periods of time during which your cluster does not have active cluster management function available. 

============================
Configuration considerations
============================


xCAT provides several configuration options for the HAMN, you can select one of the option based on your failover requirements and hardware configuration, the following configuration considerations should be able to help you to make the decision. 

******************************
Data synchronization mechanism
******************************

The data synchronization is important for any high availability configuration. When the xCAT management node failover occurs, the xCAT data needs to be exactly the same before failover, and some of the operating system configuration should also be synchronized between the two management nodes. To be specific, the following data should be synchronized between the two management nodes to make the xCAT HAMN work: 

* xCAT database 
* xCAT configuration files, like /etc/xcat, ~/.xcat, /opt/xcat 
* The configuration files for the services that are required by xCAT, like named, DHCP, apache, nfs, ssh, etc. 
* The operating systems images repository and users customization data repository, the /install directory contains these repositories in most cases. 

There are a lot of ways for data syncronization, but considering the specific xCAT HAMN requirements, only several of the data syncronziation options are practical for xCAT HAMN. 

**1\. Move physical disks between the two management nodes**: if we could physically move the hard disks from the failed management node to the backup management node, and bring up the backup management node, then both the operating system and xCAT data will be identical between the new management node the failed management node. RAID1 or disk mirroring could be used to avoid the disk be a single point of failure. 

**2\. Shared data**: the two management nodes use the single copy of xCAT data, no matter which management node is the primary MN, the cluster management capability is running on top of the single data copy. The acess to the data could be done through various ways like shared storage, NAS, NFS, samba etc. Based on the protocol being used, the data might be accessable only on one management node at a time or be accessable on both management nodes in parellel. If the data could only be accessed from one management node, the failover process need to take care of the data access transition; if the data could be accessed on both management nodes, the failover does not need to consider the data access transition, it usually means the failover process could be faster. 

Warning: Running database through network file system has a lot of potential problems and is not practical, however, most of the database system provides database replication feature that can be used to synronize the database between the two management nodes. 

**3\. Mirroring**: each of the management node has its own copy of the xCAT data, and the two copies of data are syncronized through mirroring mechanism. DRBD is used widely in the high availability configuration scenarios, to provide data replication by mirroring a whole block device via network. If we put all the important data for xCAT onto the DRBD devices, then it could assure the data is synchronized between the two management nodes. Some parallel file system also provides capability to mirror data through network. 

*************************************
Manual failover VS automatic failover
*************************************

When the primary management node fails, the backup management node could automatically take over, or the administrator has to perform some manual procedure to finish the failover. In general, the automatic failover takes less time to detect the failure and perform and failover, comparing with the manual failover, but the automatic failover requires more complex configuration. We could not say the automatic failover is better than the manual failover in all cases, the following factors should be considered when deciding the manual failover or automatic failover: 

**1\. How long the cluster could survive if the management node is down?**

If the cluster could not survive for more than several minutes, then the automatic failover might be the only option; if the compute nodes could run without the management node, at least for a while, then the manual failover could be an option. 

From xCAT perspective, if the management node needs to provide network services like DHCP, named, ntp or nfs to the compute nodes, then the cluster probably could not survive too long if the management node is down; if the management node only performs hardware control and some other management capabilities, then the failed management node may not cause too much trouble for the cluster. xCAT provides various options for configuring if the compute nodes rely on the network services on the management node. 

**2\. Configuration complexity**

The configuration for the high availability applications is usually complex, it may take a long time to configure, debug and stablize the high availability configuration. 

**3\. Maintenance effort**

The automatic failover brings in several high availability applications, after the initial configuration is done, additional maintenance effort will be needed. For example, taking care of the high availability applications during cluster update, the updates for the high availability applications themselves, trouble shooting any problems with the high availability applications. A simple question may be able to help you to decide: could you get technical support if some of the high availability applications run into problems? All software has bugs ... 

*********************
Configuration Options
*********************

The combinations of data synchronization mechanism and manual/automatic failover indicates different HAMN configuration options, the table below list all the combinations (the bold numbers are the combinations xCAT has documented and tested): 

+-------------------+-------------------------+-----------------+--------------+
|#                  | **Move physical disks** | **Shared data** | **Mirroring**|
+-------------------+-------------------------+-----------------+--------------+
|Manual Failover    | **1**                   | **2**           | 3            |
+-------------------+-------------------------+-----------------+--------------+
|Automatic Failover | 4                       | 5               | **6**        |
+-------------------+-------------------------+-----------------+--------------+


