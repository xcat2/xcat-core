.. include:: ../../common/discover/manually_define.rst

Manually define node means the admin know detailed information of the physical server. Then define it into xCAT database with commands.

.. include:: schedule_environment.rst

Manually define node
--------------------

To add a node object::

    #nodeadd cn1 groups=pkvm,all

To change node attributes::

    #chdef cn1 mgt=ipmi cons=ipmi ip=10.0.101.1 netboot=petitboot
    #chdef cn1 bmc=50.0.101.1 bmcusername=ADMIN bmcpassword=admin
    #chdef cn1 installnic=mac primarynic=mac mac=6c:ae:8b:6a:d4:e4 

The manually defined node will be like this::

    # lsdef cn1
    Object name: cn1
        bmc=50.0.101.1
        bmcpassword=admin
        bmcusername=ADMIN
        cons=ipmi
        groups=pkvm,all
        installnic=mac
        ip=10.0.101.1
        mac=6c:ae:8b:6a:d4:e4
        mgt=ipmi
        netboot=petitboot
        postbootscripts=otherpkgs
        postscripts=syslog,remoteshell,syncfiles
        primarynic=mac
