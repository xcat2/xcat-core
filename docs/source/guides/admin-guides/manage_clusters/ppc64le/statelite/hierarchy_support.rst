Hierarchy Support
-----------------

In the ``statelite`` environment, the service node needs to provide NFS service for the compute node with ``statelite``, the service nodes must to be setup with diskfull installation.

Setup the diskfull service node
```````````````````````````````

#. Setup one diskfull service node at first.

#. Since statelite is a kind of NFS-hybrid method, you should remove the installloc attribute in the site table. This makes sure that the service node does not mount the ``/install`` directory from the management node on the service node.

Generate the statelite image
````````````````````````````

To generate the statelite image for your own profile follow instructions in :doc:`Customize your statelite osimage <./provision_statelite>`. 

``NOTE``: if the NFS directories defined in the litetree table are on the service node, it is better to setup the NFS directories in the service node following the chapter.

Sync the ``/install`` directory
```````````````````````````````

The command prsync is used to sync the ``/install`` directory to the service nodes.

Run the following: ::

    cd /
    prsync install <sn>:/

``<sn>`` is the hostname of the service node you defined.

Since the ``prsync`` command will sync all the contents in the ``/install`` directory to the service nodes, the first time will take a long time. But after the first time, it will take very short time to sync.

``NOTE``: if you make any changes in the ``/install`` directory on the management node, and the changes can affect the statelite image, you need to sync the ``/install`` directory to the service node again.

Set the boot state to statelite
```````````````````````````````

You can now deploy the node: ::

    rinstall <noderange> osimage=rhel5.3-x86_64-statelite-compute

This will create the necessary files in ``/tftpboot`` for the node to boot correctly.
