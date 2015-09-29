.. _Using-Prescript-label:

Using Prescript
---------------

The prescript table will allow you to run scripts before the install process. This can be helpful for performing advanced actions such as manipulating system services or configurations before beginning to install a node, or to prepare application servers for the addition of new nodes. Check the man page for more information. 

``man prescripts``

The scripts will be run as root on the MASTER for the node. If there is a service node for the node, then the scripts will be run on the service node.

Identify the scripts to be run for each node by adding entries to the prescripts table: :: 

   tabedit prescripts
   Or: 
   chdef -t node -o <noderange> prescripts-begin=<beginscripts> prescripts-end=<endscripts>
   Or: 
   chdef -t group -o <nodegroup> prescripts-begin=<beginscripts> prescripts-end=<endscripts>

   tabdump prescripts
   #node,begin,end,comments,disable

   begin or prescripts-begin - This attribute lists the scripts to be run at the beginning of the nodeset.
   end or prescripts-end - This attribute lists the scripts to be run at the end of the nodeset.
 
Format for naming prescripts
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The general format for the prescripts-begin or prescripts-end attribute is: ::

    [action1:]s1,s2...[|action2:s3,s4,s5...] 

    where: 

    - action1 and action2 are the nodeset actions ( 'install', 'netboot',etc) specified in the command . 

    - s1 and s2 are the scripts to run for _action1_ in order. 

    - s3, s4, and s5 are the scripts to run for action2.

If actions are omitted, the scripts apply to all actions.

Examples:

    * myscript1,myscript2 - run scripts for all supported commands 
    * install:myscript1,myscript2|netboot:myscript3

Run scripts 1,2 for nodeset(install), runs script3 for nodeset(netboot).

All the scripts should be copied to /install/prescripts directory and made executable for root and world readable for mounting. If you have service nodes in your cluster with a local /install directory (i.e. /install is not mounted from the xCAT management node to the service nodes), you will need to synchronize your /install/prescripts directory to your service node anytime you create new scripts or make changes to existing scripts.

The following two environment variables will be passed to each script:

    * NODES - a comma separated list of node names on which to run the script
    * ACTION - current nodeset action.

By default, the script will be invoked once for all nodes. However, if **'#xCAT setting:MAX_INSTANCE=number'** is specified in the script, the script will be invoked for each node in parallel, but no more than number of instances specified in **number** will be invoked at at a time. 

Exit values for prescripts
~~~~~~~~~~~~~~~~~~~~~~~~~~

If there is no error, a prescript should return with 0. If an error occurs, it should put the error message on the stdout and exit with 1 or any non zero values. The command (nodeset for example) that runs prescripts can be divided into 3 sections.

    #. run begin prescripts
    #. run other code
    #. run end prescripts

If one of the prescripts returns 1, the command will finish the rest of the prescripts in that section and then exit out with value 1. For example, a node has three begin prescripts s1,s2 and s3, three end prescripts s4,s5,s6. If s2 returns 1, the prescript s3 will be executed, but other code and the end prescripts will not be executed by the command.

If one of the prescripts returns 2 or greater, then the command will exit out immediately. This only applies to the scripts that do not have **'#xCAT setting:MAX_INSTANCE=number'**.



