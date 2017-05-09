``rinv`` - Remote Hardware Inventory
====================================

When you have a lot of physical machines in one place, the most important thing is identify which is which. Mapping the model type and/or serial number of a machine with its host name. Command ``rinv`` is involved in such a situation. With this command, most of the important information to distinct one machine from all the others can be obtained remotely.

To get all the hardware information, which including the model type, serial number, firmware version, detail configuration, et al. ::

    rinv cn1 all

As an example, in order to get only the information of firmware version, the following command can be used. ::

    rinv cn1 firm

