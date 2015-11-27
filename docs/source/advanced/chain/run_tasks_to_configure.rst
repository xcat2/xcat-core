Run Task List to Configure a Node
=================================

Run the ``nodeset`` command to set the tasks for the compute node and ``rpower <node> reset`` to initiate the running of tasks. ::

    nodeset $node runimage=http://$MASTER/image.tgz,osimage=<image_name>
    rpower $node reset

In this example, the ``runimage`` will be run first, and then the image <image_name> will be deployed to the node.

During ``nodeset`` your request is put into the ``currstate`` attribute. The ``chain`` attribute is not used. The task in the ``currstate`` attribute will be passed to genesis and executed. If additional tasks are defined in the ``currchain`` attribute, these tasks will be run after the tasks in the ``currstate`` attribute are run.

