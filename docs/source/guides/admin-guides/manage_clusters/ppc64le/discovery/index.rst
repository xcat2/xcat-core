Hardware Discovery & Define Node
================================

In order to manage machines using xCAT, the machines need to be defined as xCAT ``node objects`` in the database. The :doc:`xCAT Objects </guides/admin-guides/basic_concepts/xcat_object/index>` documentation describes the process for manually creating ``node objects`` one by one using the xCAT ``mkdef`` command.  This is valid when managing a small sizes cluster but can be error prone and cumbersome when managing large sized clusters.

xCAT provides several *automatic hardware discovery* methods to assist with hardware discovery by helping to simplify the process of detecting service processors (SP) and collecting various server information. The following are methods that xCAT supports:


.. toctree::
   :maxdepth: 2

   mtms/index.rst
   switch_discovery.rst
   seq_discovery.rst
   manually_define.rst
   manually_discovery.rst


Following are the brief characteristics and adaptability of each method, you can select a proper one according to your cluster size and other consideration.

* **Manually Define Nodes**

  Manually collect information for target servers and manually define them to xCAT **Node Object** through ``mkdef`` command.

  This method is recommended for small cluster which has less than 10 nodes.

  * pros

    No specific configuration and procedure required and very easy to use.

  * cons

    It will take additional time to configure the SP (Management Modules like: BMC, FSP) and collect the server information like MTMS (Machine Type and Machine Serial) and Host MAC address for OS deployment ...

    This method is inefficient and error-prone for a large number of servers.

* **MTMS-based Discovery**

  **Step1**: **Automatically** search all the servers and collect server MTMS information.

  **Step2**: Define the searched server to a **Node Object** automatically. In this case, the node name will be generated based on the **MTMS** string. The admin can rename the **Node Object** to a reasonable name like **r1u1** (It means the physical location is in Rack1 and Unit1).

  **Step3**: Power on the nodes, xCAT discovery engine will update additional information like the **MAC for deployment** for the nodes.

  This method is recommended for the medium scale of cluster which has less than 100 nodes.

  * pros

    With limited effort to get the automatic discovery benefit.

  * cons

    Compared to **Switch-based Discovery**, the admin needs to be involved to rename the automatically discovered node to a reasonable name (optional). It's hard to rename the node to a location-based name for a large number of server.

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

