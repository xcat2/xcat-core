Configure routes
-----------------

There are 2 ways to configure OS route in xCAT:

  * ``makeroutes``: command to add or delete routes on the management node or any given nodes.
  * ``setroute``: script to replace/add the routes to the node, it can be used in postscripts/postbootscripts.

``makeroutes`` or ``setroute`` will modify OS temporary route, it also modifies persistent route in ``/etc/sysconfig/static-routes`` file.

Before using ``makeroutes`` or ``setroute`` to configure OS route, details of the routes data such as routename, subnet, net mask and gateway should be stored in ``routes`` table.

**Notes**: the ``gateway`` in the ``networks`` table assigns ``gateway`` from DHCP to compute node, so if use ``makeroutes`` or ``setroute`` to configure OS static route for compute node, make sure there is no ``gateway`` for the specific network in ``networks`` table.

Configure ``routes`` table
``````````````````````````

#. Store default route data in ``routes`` table: ::

    chdef -t route defaultroute net=default mask=255.0.0.0 gateway=10.0.0.101

#. Store additional route data in ``routes`` table: ::

    chdef -t route 20net net=20.0.0.0 mask=255.0.0.0 gateway=0.0.0.0 ifname=eth1

#. Check data in ``routes`` table: ::

    tabdump routes
    #routename,net,mask,gateway,ifname,comments,disable
    "30net","30.0.0.0","255.0.0.0","0.0.0.0","eth2",,
    "20net","20.0.0.0","255.0.0.0","0.0.0.0","eth1",,
    "defaultroute","default","255.0.0.0","10.0.0.101",,,

Use ``makeroutes`` to configure OS route on xCAT management node
''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''''

#. define the names of the routes to be setup on the management node in ``site`` table: ::

    chdef -t site mnroutenames="defaultroute,20net"
    lsdef -t site clustersite -i mnroutenames
        Object name: clustersite
            mnroutenames=defaultroute,20net

#. add all routes from the ``mnroutenames`` to the OS route table for the management node: ::

    makeroutes

#. add route ``20net`` and ``30net`` to the OS route table for the management node: ::

    makeroutes -r 20net,30net

#. delete route ``20net`` from the OS route table for the management node: ::

    makeroutes -d -r 20net

Use ``makeroutes`` to configure OS route for compute node
'''''''''''''''''''''''''''''''''''''''''''''''''''''''''

#. define the names of the routes to be setup on the compute node: ::

    chdef -t cn1 routenames="defaultroute,20net"

#. add all routes from the ``routenames`` to the OS route table for the compute node: ::

    makeroutes cn1

#. add route ``20net`` and ``30net`` to the OS route table for the compute node: ::

    makeroutes cn1 -r 20net,30net

#. delete route ``20net`` from the OS route table for the compute node: ::

    makeroutes cn1,cn2 -d -r 20net

Use ``setroute`` to configure OS route for compute node
'''''''''''''''''''''''''''''''''''''''''''''''''''''''

#. define the names of the routes to be setup on the compute node: ::

    chdef -t cn1 routenames="defaultroute,20net"

#. If adding ``setroute [replace | add]`` into the node’s postscripts list, ``setroute`` will be executed during OS deployment on compute node to replace/add routes from ``routenames``: ::

    chdef cn1 -p postscripts="setroute replace"

#. Or if the compute node is already running, use ``updatenode`` command to run ``setroute [replace | add]``  postscript: ::

    updatenode cn1 -P "setroute replace"

Check result
````````````

#. Use ``route`` command in xCAT management node to check OS route table.

#. Use ``xdsh cn1 route`` to check compute node OS route table.
