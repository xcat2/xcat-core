Quick Start Guide
=================

If xCAT looks suitable for your requirement, following steps are recommended procedure to set up an xCAT cluster.

#. Find a server as your xCAT management node

   The server can be a bare-metal server or a virtual machine. The major factor for selecting a server is the number of machines in your cluster. The bigger the cluster is, the performance of server need to be better.

   ``NOTE``: The architecture of xCAT management node is recommended to be same as the target compute node in the cluster.

#. Install xCAT on your selected server

   The server which installed xCAT will be the **xCAT Management Node**.

   Refer to the doc: :doc:`xCAT Install Guide <../guides/install-guides/index>` to learn how to install xCAT on a server.

#. Start to use xCAT management node

   Refer to the doc: :doc:`xCAT Admin Guide <../guides/admin-guides/index>`.

#. Discover target nodes in the cluster

   You have to define the target nodes in the xCAT database before managing them.

   For a small cluster (less than 5), you can collect the information of target nodes one by one and then define them manually through ``mkdef`` command.

   For a bigger cluster, you can use the automatic method to discover the target nodes. The discovered nodes will be defined to xCAT database. You can use ``lsdef`` to display them.

   Refer to the doc: :doc:`xCAT discovery Guide <../guides/admin-guides/manage_clusters/ppc64le/discovery/index>` to learn how to discover and define compute nodes.

#. Try to perform the hardware control against the target nodes

   Now you have the node definition. Verify the hardware control for defined nodes is working. e.g. ``rpower <node> stat``.

   Refer to the doc: :doc:`Hardware Management </guides/admin-guides/manage_clusters/ppc64le/management>` to learn how to perform the remote hardware control.

#. Deploy OS on the target nodes

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

When managing a cluster with hundreds or thousands of nodes, operating on many nodes in parallel might be necessary. xCAT has some parallel commands for that.

     * Parallel shell
     * Parallel copy
     * Parallel ping

   Refer to the :doc:`/guides/admin-guides/manage_clusters/ppc64le/parallel_cmd` to learn how to use parallel commands.

#. Contribute to xCAT (Optional)

While using xCAT, if you find something (code, documentation, ...) that can be improved and you want to contribute that to xCAT, do that for your and other xCAT users benefit. And welcome to xCAT community!

   Refer to the :doc:`/developers/index` to learn how to contribute to xCAT community.

