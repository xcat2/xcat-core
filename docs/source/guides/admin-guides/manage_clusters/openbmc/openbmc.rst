Manually Define Nodes
=====================

**Manually Define Node** means the admin knows the detailed information of the physical server and manually defines it into xCAT database with ``mkdef`` commands.

In this document, the following configuration is used in the example

Compute Node info::

    CN Hostname: cn1
    BMC Address: 50.0.101.1
    OpenBMC username: root
    OpenBMC Password: 0penBMC

Execute ``mkdef`` command to define the node: ::

    mkdef -t node cn1 groups=openbmc,all mgt=openbmc cons=openbmc bmc=50.0.101.1 bmcusername=root bmcpassword=OpenBMC

The manually defined node will be like this::

    # lsdef cn1
    Object name: cn1
        bmc=50.0.101.1
        bmcpassword=OpenBMC
        bmcusername=root
        cons=openbmc
        groups=openbmc,all
        mgt=openbmc
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles

Hardware Management
===================

Remote Power Control
````````````````````

The next important thing is to control the power of a remote physical machine. For this purpose, ``rpower`` command is involved. ::

    rpower cn1 on
    rpower cn1 off
    rpower cn1 boot
    rpower cn1 reset

Get the current rpower state of a machine, refer to the example below. ::

    # rpower cn1 state
    cn1: on

Remote Console
``````````````

In order to get the command line console remotely. xCAT provides the ``rcons`` command.

#. Make sure the ``conserver`` is configured by running ``makeconservercf``.

#. After that, you can get the command line console for a specific machine with the ``rcons`` command ::

    rcons cn1

