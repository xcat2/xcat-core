Hardware Management
===================

Basic Operation
---------------

The Beacon Light
````````````````

Most of modern enterprise level server machines have LEDs installed on their front panel and/or rear panel, which are called beacon lights. When this light has been turned on, the system administrator can use this light to indicate one physical machine out of a bunch of enclosures in a server frame. It makes life easier.

With xCAT, the end user can turn the beacon light on or off with the commands show below. ::

    rbeacon cn1 on
    rbeacon cn1 off

The current state of the beacon light can not be queried remotely. As a workaround, one can always use the ``rbeacon`` command to turn all the beacon lights in one frame off, and then turn a particular beacon light on. ::

    rbeacon a_group_of_cn off
    rbeacon cn5 on

Remote Power Control
````````````````````

The next important thing is to control the power of a remote physical machine. For this purpose, ``rpower`` command is involved. ::

    rpower cn1 on
    rpower cn1 off

In order to reboot a remote physical machine, run ::

    rpower cn1 boot

Or do a hardware reset, run ::

    rpower cn1 reset

Get the current rpower state of a machine, refer to the example below. ::

    # rpower cn1 state
    cn1: Running

Remote Console
``````````````

Most enterprise level servers do not have video adapters installed with the machine. Meaning, the end user can not connect a monitor to the machine and get display output. In most cases, the console can be viewed using the serial port or LAN port, through Serial-over-LAN. Serial cable or network cable are used to get a command line interface of the machine. From there, the end user can get the basic machine booting information, firmware settings interface, local command line console, etc.

In order to get the command line console remotely. xCAT provides the ``rcons`` command.

#. Make sure the ``conserver`` is configured by running ``makeconservercf``.

#. Check if the ``conserver`` is up and running ::

    ps ax | grep conserver

#. If ``conserver`` is not running, start ::

    [sysvinit] service conserver start 
    [systemd] systemctl start conserver.service

or restart, if changes to the configuration were made ::    

    [sysvinit] service conserver restart 
    [systemd] systemctl restart conserver.service


#. After that, you can get the command line console for a specific machine with the ``rcons`` command ::

    rcons cn1

Advanced operation
------------------

Remote Hardware Inventory
`````````````````````````

When you have a lot of physical machines in one place, the most important thing is identify which is which. Mapping the model type and/or serial number of a machine with its host name. Command ``rinv`` is involved in such a situation. With this command, most of the important information to distinct one machine from all the others can be obtained remotely.

To get all the hardware information, which including the model type, serial number, firmware version, detail configuration, et al. ::

    rinv cn1 all

As an example, in order to get only the information of firmware version, the following command can be used. ::

    rinv cn1 firm

Remote Hardware Vitals
``````````````````````

Collect runtime information from running physical machine is also a big requirement for real life system administrators. This kind of information includes, temperature of CPU, internal voltage of particular socket, wattage with workload, speed of cooling fan, et al.

In order to get such information, use ``rvitals`` command. This kind of information varies among different model types of the machine. Thus, check the actual output of the ``rvitals`` command against your machine, to verify which kinds of information can be extracted. The information may change after the firmware update of the machine.  ::

    rvitals cn1 all

As an example, get only the temperature information of a particular machine. ::

    rvitals cn1 temp

Firmware Updating
`````````````````

For OpenPOWER machines, use the ``rflash`` command to update firmware.

Check firmware version of the node and the HPM file:  ::

    rflash cn1 -c /firmware/8335_810.1543.20151021b_update.hpm

Update node firmware to the version of the HPM file

::

    rflash cn1 /firmware/8335_810.1543.20151021b_update.hpm

Configures Nodes' Service Processors
````````````````````````````````````

Here comes the command, ``rspconfig``. It is used to configure the service processor of a physical machine. On a OpenPower system, the service processor is the BMC, Baseboard Management Controller. Various variables can be set through the command. Also notice, the actual configuration may change among different machine-model types.

Examples

To turn on SNMP alerts for cn5: ::

    rspconfig cn5 alert=on
