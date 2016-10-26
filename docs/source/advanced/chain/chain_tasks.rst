Task Type
=========

xCAT supports following types of task which could be set in the chain:

* runcmd ::

    runcmd=<cmd>

Currently only the ``bmcsetup`` command is officially supplied by xCAT to run to configure the bmc of the compute node. You can find the ``bmcsetup`` in /opt/xcat/share/xcat/netboot/genesis/<arch>/fs/bin/. You also could create your command in this directory and adding it to be run by ``runcmd=<you cmd>``. ::

    runcmd=bmcsetup

**Note**: the command ``mknb <arch>`` is needed before reboot the node.

* runimage ::

    runimage=<URL>

**URL** is a string which can be run by ``wget`` to download the image from the URL. The example could be: ::
  
    runimage=http://<IP of xCAT Management Node>/<dir>/image.tgz

The ``image.tgz`` **must** have the following properties:
  * Created using the ``tar zcvf`` command
  * The tarball must include a ``runme.sh`` script to initiate the execution of the runimage

To create your own image, reference :ref:`creating image for runimage <create_image_for_runimage>`. 

**Tip**: You could try to run ``wget http://<IP of xCAT Management Node>/<dir>/image.tgz`` manually to make sure the path has been set correctly.

* osimage ::

   osimage=<image name>

This task is used to specify the image that should be deployed onto the compute node.

* shell

Causes the genesis kernel to create a shell for the administrator to log in and execute commands.

* standby

Causes the genesis kernel to go into standby and wait for tasks from the chain. ... 

