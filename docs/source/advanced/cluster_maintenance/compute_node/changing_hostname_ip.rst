Changing the hostname/IP address
================================

Background
----------

If the hostname or ip address has already been modified on compute nodes, you
can follow the steps to change the configuration in xcat.

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
     fd03:2e76:8631::/64  (network)

   Change the networks table definitions, take ``10_0_0_0-255_0_0_0`` as a example ::

     chdef -t network 10_0_0_0-255_0_0_0 gateway=10.0.0.103

#. Change the hostname in the xCAT database (This command only supports one node
   at a time). For many nodes you will have to write a script. ::

    # changes node1 to node2 in the database
    chdef -t node -o node1 -n node2

#. Change the hostname and ip address in the ``/etc/hosts`` file

   - If you do not use the hosts table in xCAT to create the ``/etc/hosts`` file,
     edit the ``/etc/hosts`` file and change your hostnames/ipaddresses entries
     directly.
   - If you use the xCAT hosts table, and your nodes are defined by name in the
     hosts table, the hosts table must be updated with the new names when
     we changed the node name using chdef command. If the hosts tables contains
     regular expression, you have to rewrite the regular expression to
     match your new hostnames/ip addresses.
   - If these is no regular expression in the hosts table, you can run ::

       # change the ip address for the new hostname in the hosts table.
       nodech <newnodename> hosts.ip="x.xx.xx.xx"
       # add host/ip records in /etc/hosts from the definition in the xCAT hosts
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
