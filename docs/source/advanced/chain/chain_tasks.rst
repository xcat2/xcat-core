Task Type
=========

xCAT supports following types of task which could be set in the chain:

* runcmd::

    runcmd=<cmd>

Currently only the ``bmcsetup`` command is officially supplied by xCAT to run to configure the bmc of the compute node. You can find the ``bmcsetup`` in /opt/xcat/share/xcat/netboot/genesis/<arch>/fs/bin/. You also could create your command in this directory and adding it to be run by ``runcmd=<you cmd>``. ::

    e.g. runcmd=bmcsetup

**Note**: the command ``mknb <arch>`` is needed before reboot the node.

* runimage::

   runimage=<URL>

**URL** is a string which can be run by ``wget`` to download the image from the URL. The example could be: ::
  
    runimage=http://$MASTER/<dir>/image.tgz

The image.tgz should can be uncompressed by ``tar xvf image.tgz``. And image.tgz should include a file named ``runme.sh`` which is a script to initiate the running of the image. Pls reference :ref:`creating image for runimage <create_image_for_runimage>` for more information about creating your own ``image``. 

**Note**: You could try to run ``wget http://$MASTER/<dir>/image.tgz`` manually to make sure the path has been set correctly.

* osimage::

   osimage=<image name>

This task is used to specify that the compute node should run the OS deployment with osimage=<image name>.

* shell

Make the genesis gets into the shell for admin to log in and run command.

* standby

Make the genesis gets into standby and waiting for the task from chain. If the compute node gets into this state, any new task set to chain.currstate will be run immediately.
