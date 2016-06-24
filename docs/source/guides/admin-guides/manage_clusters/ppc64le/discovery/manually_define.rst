Manually Define Nodes
=====================

**Manually Define Node** means the admin knows the detailed information of the physical server and manually defines it into xCAT database with ``mkdef`` commands.

.. include:: schedule_environment.rst

Manually Define Node
--------------------

Execute ``mkdef`` command to define the node: ::

    mkdef -t node cn1 groups=powerLE,all mgt=ipmi cons=ipmi ip=10.0.101.1 netboot=petitboot bmc=50.0.101.1 bmcusername=ADMIN bmcpassword=admin installnic=mac primarynic=mac mac=6c:ae:8b:6a:d4:e4

The manually defined node will be like this::

    # lsdef cn1
    Object name: cn1
        bmc=50.0.101.1
        bmcpassword=admin
        bmcusername=ADMIN
        cons=ipmi
        groups=powerLE,all
        installnic=mac
        ip=10.0.101.1
        mac=6c:ae:8b:6a:d4:e4
        mgt=ipmi
        netboot=petitboot
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        primarynic=mac
