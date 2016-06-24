Change Zones
============


After you create a zone, you can use the :doc:`chzone </guides/admin-guides/references/man1/chzone.1>` command to make changes. Some of the things you can do are the following:

* Add nodes to the zone
* Remove nodes from the zone
* Regenerated the keys
* Change sshbetweennodes setting
* Make it the default zone

The following command will add node1-node10 to zone1 and create a group called zone1 on each of the nodes. ::

    chzone zone1 -a node1-node10 -g

The following command will remove node20-node30 from zone1 and remove the group zone1 from those nodes. ::

    chzone zone1 -r node2--node30 -g

The following command will change zone1 such that root cannot ssh between the nodes without entering a password. ::

    #chzone zone1 -s no

    #lsdef -t zone zone1
    Object name: zone1
       defaultzone=no
       sshbetweennodes=no
       sshkeydir=/etc/xcat/sshkeys/zone1/.ssh

The following command will change zone1 to the default zone. 

**Note**: you must use the ``-f`` flag to force the change. There can only be one default zone in the ``zone`` table. ::

    #chzone zone1 -f --defaultzone

    #lsdef -t zone -l
    Object name: xcatdefault
       defaultzone=no
       sshbetweennodes=yes
       sshkeydir=/root/.ssh
    Object name: zone1
       defaultzone=yes
       sshbetweennodes=no
       sshkeydir=/etc/xcat/sshkeys/zone1/.ssh

Finally, if your root ssh keys become corrupted or compromised you can regenerate them. ::

    chzone zone1 -K

or ::

    chzone zone1 -k <path to SSH RSH private key>

As with the :doc:`mkzone </guides/admin-guides/references/man1/mkzone.1>` commands, these commands have only changed the definitions in the database, you must run the following to distribute the keys. ::

     updatenode mycompute -k

or ::

     xdsh mycompute -K

