Overview
========

xCAT enables you to easily manage large number of servers for any type of technical computing workload.

xCAT is known for exceptional scaling, wide variety of supported hardware, operating systems, and virtualization platforms. And complete day0 setup capabilities.

xCAT Differentiators
--------------------

* xCAT Scales

  Beyond all IT budgets. 100,000s of nodes with distributed architecture.

* Open Source

  Eclipse Public License. You can also buy support contracts.

* Support Multiple OS

  RH, Sles, Ubuntu, Debian, CentOS, Fedora, Scientific Linux, Oracle Linux, Windows, Esxi, RHEV

* Support Multiple Hardware

  IBM Power, IBM Power LE, x86_64

* Support Multiple Virtulization

  IBM zVM, IBM PowerKVM, KVM, ESXI, XEN

* Support Multiple Installation Options

  Diskful (Install to Hard Disk), Diskless (Run in memory), Cloning

* Built in Automatic discovery

  No need to power on one machine at a time to discover. Also, nodes that fail can be replaced and back in action by just powering new one on.

* Rest API

  Support Rest API for the third-party software to integrate.

Features
--------

#. Discover the hardware servers

   * Manually define 
   * MTMS-based discovery
   * Switch-based discovery
   * Sequential-based discovery

#. Execute remote system management against the discovered server

   * Remote power control
   * Remote console support
   * Remote inventory/vitals information query
   * Remote event log query

#. Provision Operating Systems on physical (Bare-metal) or virtual machines

   * RHEL
   * SLES
   * Ubuntu
   * Debian
   * Fedora
   * CentOS
   * Scientific Linux
   * Oracle Linux
   * PowerKVM
   * Esxi
   * RHEV
   * Windows
   * AIX

#. Provision machines in

   * Diskful (Scripted install, Clone)
   * Stateless

#. Install and configure user applications

   * During OS install
   * After the OS install
   * HPC products - GPFS, Parallel Environment, LSF, compilers ...
   * Big Data - Hadoop, Symphony
   * Cloud - Openstack, Chef

#. Parallel system management

   * Parallel shell (Run shell command against nodes in parallel)
   * Parallel copy
   * Parallel ping

#. Integrate xCAT in Cloud
   * Openstack
   * SoftLayer

Matrix of Supported OS and Hardware
-----------------------------------

+-------+-------+-------+-----+-------+--------+--------+--------+
|       | Power | Power | zVM | Power | x86_64 | x86_64 | x86_64 |
|       |       | LE    |     | KVM   |        | KVM    | Esxi   |
+=======+=======+=======+=====+=======+========+========+========+
|RHEL   | yes   | yes   | yes | yes   | yes    | yes    | yes    |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+
|SLES   | yes   | yes   | yes | yes   | yes    | yes    | yes    |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+
|Ubuntu | no    | yes   | no  | yes   | yes    | yes    | yes    |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+
|CentOS | no    | no    | no  | no    | yes    | yes    | yes    |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+
|AIX    | yes   | no    | no  | no    | no     | no     | no     |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+
|Windows| no    | no    | no  | no    | yes    | yes    | yes    |
|       |       |       |     |       |        |        |        |
+-------+-------+-------+-----+-------+--------+--------+--------+

xCAT Architecture
-----------------

The following diagram shows the basic structure of xCAT:

.. image:: Xcat-arch.png

Mgmt Node (xCAT Management Node):
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

Brief Steps to Set Up an xCAT Cluster
-------------------------------------

If xCAT looks suitable for your requirement, following steps are recommended procedure to set up an xCAT cluster.

#. Find a server as your xCAT management node

   The server can be a bare-metal server or a virtual machine. The major factor to select a server is the machine number of your cluster. The bigger the cluster is, the performance of server need to be better.

   ``NOTE``: The architecture of xCAT management node is recommended to be same with the target compute node in the cluster.

#. Install xCAT on your selected server

   The server which installed xCAT will be the **xCAT Management Node**.

   Refer to the doc: :doc:`xCAT Install Guide <../guides/install-guides/index>` to learn how to install xCAT on a server.

#. Start to use xCAT management node

   Refer to the doc: :doc:`xCAT Admin Guide <../guides/admin-guides/index>`.

#. Discover target nodes in the cluster

   You have to define the target nodes to the xCAT database before managing them.

   For a small cluster (less than 5), you can collect the information of target nodes one by one and then define them manually through ``mkdef`` command.

   For a bigger cluster, you can use the automatic method to discover the target nodes. The discovered nodes will be defined to xCAT database. You can use ``lsdef`` to display them.

   Refer to the doc: :doc:`xCAT discovery Guide <../guides/admin-guides/manage_clusters/ppc64le/discovery/index>` to learn how to discover and define compute nodes.

#. Try to perform the hardware control against the target nodes

   Now you have the node definition. Take a try to confirm the hardware control for defined nodes is working. e.g. ``rpower <node> stat``.

   Refer to the doc: :doc:`Hardware Management <../guides/admin-guides/manage_clusters/ppc64le/management/index>` to learn how to perform the remote hardware control.

#. Deploy OS for the target nodes

   * Prepare the OS images
   * Customize the OS images (Optional)
   * Perform the OS deployment

   Refer to the doc: :doc:`Diskful Install <../guides/admin-guides/manage_clusters/ppc64le/diskful/index>`, :doc:`Diskless Install <../guides/admin-guides/manage_clusters/ppc64le/diskless/index>` to learn how to deploy OS for a target node.

#. Update the OS after the deployment

   You may require to update the OS of certain target nodes after the OS deployment, try the ``updatenode`` command. ``updatenode`` command can execute the following tasks for target nodes:

     * Install additional software/application for the target nodes
     * Sync some files to the target nodes
     * Run some postscript for the target nodes

    Refer to the doc: :doc:`Updatenode <../guides/admin-guides/manage_clusters/ppc64le/updatenode>` to learn how to use ``updatenode`` command.

#. Run parallel commands

   When you manage a cluster which has hundreds or thousands of nodes, you always need to do something for a bunch of nodes in parallel. xCAT has some parallel commands can help you on these task.

     * Parallel Shell
     * Parallel copy
     * parallel ping

   Refer to the doc: :doc:`Parallel Commands <../guides/admin-guides/manage_clusters/ppc64le/parallel_cmd>` to learn how to use parallel commands.

#. Contribute to xCAT (OPtional)

   During your using of xCAT, if you find something (code, document ...) that can be improved and you want to contribute that to xCAT, please do that for the behalf of yours and other xCAT user's. And welcome to xCAT community!

   Refer to the doc: :doc:`Developer Guide <../developers/index>` to learn how to contribute to xCAT community.

