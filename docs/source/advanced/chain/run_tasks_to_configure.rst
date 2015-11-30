Run Task List to Configure a Node
=================================

Run the ``nodeset`` command to set the tasks for the compute node and ``rpower <noderange> reset`` to initiate the running of tasks. ::

    nodeset <noderange> runimage=http://<IP of xCAT Management Node>/image.tgz,osimage=<image_name>
    rpower <noderange> reset

In this example, the ``runimage`` will be run first, and then the image <image_name> will be deployed to the node.


