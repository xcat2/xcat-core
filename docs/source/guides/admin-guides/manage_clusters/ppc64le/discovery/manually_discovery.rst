.. include:: ../../common/discover/manually_discovery.rst

If you have a few nodes which were not discovered by automated hardware discovery process, you can find them in ``discoverydata`` table using the ``nodediscoverls`` command. The undiscovered nodes are those that have a discovery method value of 'undef' in the ``discoverydata`` table.

Display the undefined nodes with the ``nodediscoverls`` command::

    #nodediscoverls -t undef
    UUID                                    NODE                METHOD         MTM       SERIAL   
    fa2cec8a-b724-4840-82c7-3313811788cd    undef               undef          8247-22L  10112CA

If you want to manually define an 'undefined' node to a specific free node name, use the nodediscoverdef(TODO) command. 

Before doing that, a node with desired IP address for host and FSP/BMC must be defined first::

    nodeadd cn1 groups=powerLE,all
    chdef cn1 mgt=ipmi cons=ipmi ip=10.0.101.1 bmc=50.0.101.1 netboot=petitboot installnic=mac primarynic=mac

For example, if you want to assign the undefined node whose uuid is ``fa2cec8a-b724-4840-82c7-3313811788cd`` to cn1, run::

    nodediscoverdef -u fa2cec8a-b724-4840-82c7-3313811788cd -n cn1

After manually defining it, the 'node name' and 'discovery method' attributes of the node will be changed. You can display the changed attributes using the ``nodediscoverls`` command::

     #nodediscoverls
     UUID                                    NODE                METHOD         MTM       SERIAL  
     fa2cec8a-b724-4840-82c7-3313811788cd    cn1                manual          8247-22L  10112CA

