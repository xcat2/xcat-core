Define Service Nodes
====================

This next part shows how to configure a xCAT Hierarchy and provision xCAT service nodes from an existing xCAT cluster.

*The document assumes that the compute nodes part of your cluster have already been defined into the xCAT database and you have successfully provisioned the compute nodes using xCAT* 


The following table illustrates the cluster being used in this example:

+----------------------+----------------------+
| Operating System     | rhels7.1             |
+----------------------+----------------------+
| Architecture         | ppc64le              |
+----------------------+----------------------+
| xCAT Management Node | xcat01               |
+----------------------+----------------------+
| Compute Nodes        | r1n01                |
| (group=rack1)        | r1n02                |
|                      | r1n03                |
|                      | ...                  |
|                      | r1n10                |
+----------------------+----------------------+
| Compute Nodes        | r2n01                |
| (group=rack1)        | r2n02                |
|                      | r2n03                |
|                      | ...                  |
|                      | r2n10                |
+----------------------+----------------------+

#. Select the compute nodes that will become service nodes 
     
        The first node in each rack, ``r1n01 and r2n01``, is selected to become the xCAT service nodes and manage the compute nodes in that rack


#. Change the attributes for the compute node to make them part of the **service** group:  ::

        chdef -t node -o r1n01,r2n01 groups=service,all 

#. When ``copycds`` was run against the ISO image, several osimages are created into the ``osimage`` table. The ones containing "service" are provided to help easily provision xCAT service nodes. ::

        # lsdef -t osimage | grep rhels7.1
          rhels7.1-ppc64le-install-compute  (osimage)
          rhels7.1-ppc64le-install-service  (osimage)   <======
          rhels7.1-ppc64le-netboot-compute  (osimage)

#. Add the service nodes to the ``servicenode`` table: ::

        chdef -t group -o service setupnfs=1 setupdhcp=1 setuptftp=1 setupnameserver=1 setupconserver=1

   **Tips/Hint**
      * Even if you do not want xCAT to configure any services, you must define the service nodes in the ``servicenode`` table with at least one attribute, set to 0, otherwise xCAT will not recognize the node as a service node**
      * See the ``setup*`` attributes in the node definition man page for the list of available services:  ``man node``
      * For clusters with subnetted management networks, you might want to set ``setupupforward=1``

#. Add additional postscripts for Service Nodes (optional) 

   By default, xCAT will execute the ``servicenode`` postscript when installed or diskless booted.  This postscript will set up the necessary credentials and installs the xCAT software on the Service Nodes.  If you have additional postscripts that you want to execute on the service nodes, copy to ``/install/postscripts`` and run the following: ::

        chdef -t group -o service -p postscripts=<mypostscript>

#. Assigning Compute Nodes to their Service Nodes 

   The node attributes ``servicenode`` and ``xcatmaster``, define which Service node will serve the particular compute node. 
   
   * ``servicenode`` - defines which Service Node the **Management Node** should send commands to (e.g ``xdsh``) and should be set to the hostname or IP address of the service node that the management node can conttact it by.
   * ``xcatmaster`` - defines which Service Node the **Compute Node** should boot from and should be set to the hostname or IP address of the service node that the compute node can contact it by.

   You must set both ``servicenode`` and ``xcatmaster`` regardless of whether or not you are using service node pools, for most scenarios, the value will be identical. ::

        chdef -t group -o rack1 servicenode=r1n01 xcatmaster=r1n01 
        chdef -t group -o rack2 servicenode=r2n01 xcatmaster=r2n01

#. Set the conserver and monserver attributes
 
   Set which service node should run the conserver (console) and monserver (monitoring) daemon for the nodes in the group. The most typical setup is to have the service node also ad as it's conserver and monserver. ::

        chdef -t group -o rack1 conserver=r1n01 monserver=r1n01
        chdef -t group -o rack2 conserver=r2n01 monserver=r2n01


