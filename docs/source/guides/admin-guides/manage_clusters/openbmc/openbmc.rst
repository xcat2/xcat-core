Manually Define Nodes
=====================

If admin knows the detailed information of the physical server, ``mkdef`` command can be used to manually define it into xCAT database.

In this document, the following configuration is used as an example

Compute Node info::

    CN Hostname: cn1
    BMC Address: 50.0.101.1
    OpenBMC username: root
    OpenBMC Password: 0penBMC

Run ``mkdef`` command to define the node: ::

    mkdef -t node cn1 groups=openbmc,all mgt=openbmc cons=openbmc bmc=50.0.101.1 bmcusername=root bmcpassword=0penBmc

The manually defined node will be ::

    # lsdef cn1
    Object name: cn1
        bmc=50.0.101.1
        bmcpassword=0penBmc 
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

``rpower`` command can be used to control the power of a remote physical machine. ::

    rpower cn1 on
    rpower cn1 off
    rpower cn1 boot
    rpower cn1 reset

To get the current rpower state of a machine: ::

    # rpower cn1 state
    cn1: on

Remote Console
``````````````

``rcons`` command can be used to get command line remote console.

#. Make sure the ``conserver`` is configured by running ``makeconservercf cn1``.

#. Start command line remote console: ::

    rcons cn1

