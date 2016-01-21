Changing the Hostname/IP address
================================

Background
----------

If the hostname or IP address has already been modified on compute nodes,
follow the steps to change the configuration in xcat.

Remove Old Provision Environment
--------------------------------

#. Remove the nodes from DNS configuration ::

    makedns -d <noderange>

#. Remove the nodes from the DHCP configuration ::

    makedhcp -d <noderange>

#. Remove the nodes from the conserver configuration ::

    makeconservercf -d <noderange>

Change Definition
-----------------

#. Change netwoks table definitions ::

      lsdef -t network -l

   The output may be like ::

     10_0_0_0-255_0_0_0  (network)
     192_168_122_0-255_255_255_0  (network)

   Change the networks table definitions, For example ``192_168_122_0-255_255_255_0``
   is a original network configuration which should be modified to
   ``192_168_123_0-255_255_255_0``::

     rmdef -t network 192_168_122_0-255_255_255_0
     mkdef -t network 192_168_123_0-255_255_255_0 net=192.168.123.0 mask=255.255.255.0

#. Change the hostname in the xCAT database (This command only supports one node
   at a time). For many nodes you will have to write a script. ::

    # changes node1 to node2 in the database
    chdef -t node -o node1 -n node2

#. Change the hostname and IP address in the ``/etc/hosts`` file

   - If you do not use the hosts table in xCAT to create the ``/etc/hosts`` file,
     edit the ``/etc/hosts`` file and change your hostname and IP address entries
     directly.
   - If you use the xCAT hosts table, and your nodes are defined by name in the
     hosts table, the hosts table must be updated with the new names when
     we changed the node name using ``chdef`` command. If the hosts tables contains
     regular expression, you have to rewrite the regular expression to
     match your new hostname and IP address.
   - If these is no regular expression in the hosts table, you can run ::

       # change the IP address for the new hostname in the hosts table.
       nodech <newnodename> hosts.ip="x.xx.xx.xx"
       # add hostname/IP records in /etc/hosts from the definition in the xCAT hosts
       # table for the <noderange>
       makehosts <noderange>

Update The Provision Environment
--------------------------------

#. Configure the new names in DNS ::

    makedns -n

#. Configure the new names in DHCP ::

    makedhcp -a

#. Configure the new names in conserver ::

    makeconservercf
