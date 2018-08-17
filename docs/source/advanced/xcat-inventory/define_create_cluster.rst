Define and create your first xCAT cluster easily
================================================

The inventory templates for 2 kinds of typical xCAT cluster is shipped. You can create your first xCAT cluster easily by making several modifications on the template. The templates can be found under ``/opt/xcat/share/xcat/inventory_templates`` on management node with ``xcat-inventory`` installed.

Currently, the inventory templates includes:

1. flat_cluster_template.yaml:

   a flat baremetal cluster, including **openbmc controlled PowerLE servers**, **IPMI controlled Power servers(commented out)**, **X86_64 servers(commented out)**

2. flat_kvm_cluster_template.yaml: a flat KVM based Virtual Machine cluster, including **PowerKVM based VM nodes**, **KVM based X86_64 VM nodes(commented out)**

The steps to create your first xCAT cluster is:

1. create a customized cluster inventory file "mycluster.yaml" based on ``flat_cluster_template.yaml`` ::

    cp /opt/xcat/share/xcat/inventory_templates/flat_cluster_template.yaml /git/cluster/mycluster.yaml

2. custmize the cluster inventory file "mycluster.yaml" by modifying the attributs in the line under token ``#CHANGEME`` according to the setup of your phisical cluster. You can create new node definition by duplicating and modifying the node definition in the template.

3. import the cluster inventory file ::

    xcat-inventory import -f /git/cluster/mycluster.yaml

Now you have your 1st xCAT cluster, you can start bring up the cluster by provision nodes.


