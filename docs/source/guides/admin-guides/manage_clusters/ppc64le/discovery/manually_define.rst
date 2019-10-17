Manually Define Nodes
=====================

**Manually Define Node** means the admin knows the detailed information of the physical server and manually defines it into xCAT database with ``mkdef`` commands.

.. include:: schedule_environment.rst

Manually Define Node
--------------------

Execute ``mkdef`` command to define the node: ::

    mkdef -t node cn1 groups=powerLE,all mgt=ipmi cons=ipmi ip=10.0.101.1 netboot=petitboot bmc=50.0.101.1 bmcusername=ADMIN bmcpassword=admin installnic=mac primarynic=mac mac=6c:ae:8b:6a:d4:e4

The manually defined node will be like this::

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


``mkdef --template`` can be used to create node definitions easily from the typical node definition templates or existing node definitions, some examples:

* creating node definition "cn2" from an existing node definition "cn1" ::

     mkdef -t node -o cn2 --template cn1 mac=66:55:44:33:22:11 ip=172.12.139.2 bmc=172.11.139.2

  except for the attributes specified (``mac``, ``ip`` and ``bmc``), other attributes of the newly created node "cn2" inherit the values of template node "cn1"

* creating a node definition "cn2" with the template "ppc64le-openbmc-template" (openbmc controlled ppc64le node) shipped by xCAT ::

     mkdef -t node -o cn2 --template ppc64le-openbmc-template mac=66:55:44:33:22:11 ip=172.12.139.2 bmc=172.11.139.2 bmcusername=root bmcpassword=0penBmc

  the unspecified attributes of newly created node "cn2" will be assigned with the default values in the template

  to list all the node definition templates available in xCAT, run ::

     lsdef -t node --template

  to display the full definition of template "ppc64le-openbmc-template", run ::

     lsdef -t node --template ppc64le-openbmc-template

  the mandatory attributes, which must be specified while creating definitions with templates, are denoted with the value ``MANDATORY:<attribute description>`` in template definition.

  the optional attributes, which can be specified optionally, are denoted with the value ``OPTIONAL:<attribute description>`` in template definition
