Create Zones
============

The first time you run  :doc:`mkzone </guides/admin-guides/references/man1/mkzone.1>`, it is going to create two zones. It will create the zone you request, but automatically add the xCAT default zone. This command creates the two zones , but does not assign it to any nodes. There is a new attribute on the nodes called **zonename**. As long as it is not defined for the node, then the node will use what is currently defined in the database as the defaultzone.

**Note**: if zones are defined in the zone table, there must be one and only one default zone. If a node does not have a zonename defined and there is no defaultzone in the zone table, it will get an error and no keys will be distribute.

For example:  ::

    #mkzone zone1

    #lsdef -t zone -l
    Object name: xcatdefault
       defaultzone=yes
       sshbetweennodes=yes
       sshkeydir=/root/.ssh
    Object name: zone1
       defaultzone=no
       sshbetweennodes=yes
       sshkeydir=/etc/xcat/sshkeys/zone1/.ssh

Another example which makes the zone and defines the nodes in the mycompute group in the zone and also automatically creates a group on each node by the zonename is the following: ::

    #makezone zone2  -a mycompute -g

    #lsdef mycompute
    Object name: node1
       groups=zone2,mycompute
       postbootscripts=otherpkgs
       postscripts=syslog,remoteshell,syncfiles
       zonename=zone2

At this time we have only created the zone, assigned the nodes and generated the SSH RSA keys to be distributed to the node. To setup the ssh keys on the nodes in the zone, run the following ``updatenode`` command. It will distribute the new keys to the nodes, it will automatically sync the zone key directory to any service nodes and it will regenerated your ``mypostscript.<nodename>`` files to include the zonename, if you are using ``precreatemypostscripts`` enabled. ::

    updatenode mycompute -k

You can also use the following command but it will not regenerated the mypostscript.<nodename> file. ::

    xdsh mycompute -K

If you need to install the nodes, then run the following commands. They will do everything during the install that the updatenode did. Running nodeset is very important, because it will regenerate the mypostscript file to include the zonename attribute. ::

     nodeset mycompute osimage=<mycomputeimage>
     rsetboot mycompute net
     rpower mycompute boot


