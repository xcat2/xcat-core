Remove Zones
============


The :doc:`rmzone </guides/admin-guides/references/man1/rmzone.1>`  command will remove a zone from the database. It will also remove the zone name from the **zonename** attribute on all the nodes currently defined in the zone and as an option ``-g`` will remove the group zonename from the nodes. The zonename attribute will be undefined, which means the next time the keys are distributed, they will be picked up from the defaultzone. It will also remove the ``/etc/xcat/sshkeys/<zonename>`` directory.

**Note**: :doc:`rmzone </guides/admin-guides/references/man1/rmzone.1>` will always remove the zonename defined on the nodes in the zone. If you use other xCAT commands and end up with a zonename defined on the node that is not defined in the zone table, when you try to distribute the keys you will get errors and the keys will not be distributed. ::

      rmzone zone1 -g

If you want to remove the default zone, you must use the ``-f`` flag. You probably only need this to remove all the zones in the zone table. If you want to change the default zone, you should use the :doc:`chzone </guides/admin-guides/references/man1/chzone.1>` command.

**Note**: if you remove the default zone and nodes have the ``zonename`` attribute undefined, you will get errors when you try to distribute keys. ::

      rmzone zone1 -g -f

As with the other zone commands, after the location of a nodes root ssh keys has changed you should use one of the following commands to update the keys on the nodes: ::

     updatenode mycompute -k

or ::

     xdsh mycompute -K

