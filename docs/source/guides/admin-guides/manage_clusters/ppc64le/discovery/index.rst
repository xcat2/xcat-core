Hardware Discovery & Define Node
================================

Have the servers to be defined as **Node Object** in xCAT is the first step to do for a cluster management.

In the chapter :doc:`xCAT Object <../../../basic_concepts/xcat_object/index>`, it describes how to create a **Node Object** through `mkdef` command. You can collect all the necessary information of target servers and define them to a **xCAT Node Object** by manually run `mkdef` command. This is doable when you have a small cluster which has less than 10 servers. But it's really error-prone and inefficiency to manually configure SP (like BMC) and collect information for a large number servers.

xCAT offers several powerful **Automatic Hardware Discovery** methods to simplify the procedure of SP configuration and server information collection. If your managed cluster has more than 10 servers, the automatic discovery is worth to take a try. If your cluster has more than 50 servers, the automatic discovery is recommended.

Following are the brief characters and adaptability of each method, you can select a proper one according to your cluster size and other consideration.

* **Manually Define Nodes**

  Manually collect information for target servers and manually define them to xCAT **Node Object** through ``mkdef`` command.

  This method is recommended for small cluster which has less than 10 nodes.

  * pros

    No specific configuration and procedure required and very easy to use.

  * cons

    It will take additional time to configure the SP (Management Modules like: BMC, FSP) and collect the server information like MTMS (Machine Type and Machine Serial) and Host MAC address for OS deployment ...

    This method is inefficiency and error-prone for a large number of servers.

* **MTMS-based Discovery**

  **Step1**: **Automatically** search all the servers and collect server MTMS information.

  **Step2**: Define the searched server to a **Node Object** automatically. In this case, the node name will be generate base on the **MTMS** string. Or admin can rename the **Node Object** to a reasonable name like **r1u1 (It means the physical location is in Rack1 and Unit1)** base on the **MTMS**.

  **Step3**: Power on the nodes, xCAT discovery engine will update additional information like the **MAC for deployment** for the nodes.

  This method is recommended for the medium scale of cluster which has less than 100 nodes.

  * pros

    With limited effort to get the automatic discovery benefit.

  * cons

    Compare to **Switch-based Discovery**, admin needs to be involved to rename the auto discovered node if wanting to give node a reasonable name. It's hard to rename the node to a location awared name for a large number of server.

* **Switch-based Discovery**

  **Step1**: **Pre-define** the **Node Object** for all the nodes in the cluster. The **Pre-defined** node must have the attributes **switch** and **switchport** defined to specify which **Switch and Port** this server connected to. xCAT will use this **Switch and Port** information to map a discovered node to certain **Pre-defined** node.

  **Step2**: Power on the nodes, xCAT discovery engine will discover node attributes and update them to certain **Pre-defined** node.

  * pros

    The whole discovery process is totally automatic.

    Since the node is physically identified by the **Switch and Port** that the server connected, if a node fail and replaced with a new one, xCAT will automatically discover the new one and assign it to the original node name since the **Switch and Port** does not change.

  * cons

    You need to plan the cluster with planned **Switch and Port** mapping for each server and switch. All the Switches need be configured with snmpv3 accessible for xCAT management node.

* **Sequential-based Discovery**

  **Step1**: **Pre-define** the **Node Object** for all the nodes in the cluster.

  **Step2**: Manually power on the node one by one. The booted node will be discovered, each new discovered node will be assigned to one of the **Pre-defined** node in **Sequential**.

  * pros

    No special configuration required like **Switch-based Discovery**. No manual rename node step required like **MTMS-based Discovery**.

  * cons

    You have to strictly boot on the node in order if you want the node has the expected name. Generally you have to waiting for the discovery process finished before power on the next one.

.. toctree::
   :maxdepth: 2

   manually_define.rst
   mtms_discovery.rst
   switch_discovery.rst
   seq_discovery.rst
   manually_discovery.rst

