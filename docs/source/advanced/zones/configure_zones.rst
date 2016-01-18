Configure Zones
===============

Setting up zones only applies to nodes. We will still use the MN root ssh keys on any devices, switches, hardware control. All ssh access to these devices is done from the MN or SN. The commands that distribute keys to these entities will not recognize zones (e.g. ``rspconfig``, ``xdsh -K --devicetype``). You should never define, the Management Node in a zone. The zone commands will not allow this.

The ssh keys will be generated and store in ``/etc/xcat/sshkeys/<zonename>/.ssh`` directory. You must not change this path. XCAT will manage and sync this directory to the service nodes as need for hierarchy.

When using zones, the **site** table **sshbetweennodes** attribute is no longer use. You will get a warning that it is no longer used, if it is set. You can just remove the setting to get rid of the warning. The **zone** table **sshbetweennodes** attribute is used so this can be assigned for each zone. When using zones, the attribute can only be set to yes/no. Lists of nodegroups are not supported as was supported in the **site** table **sshbetweennodes** attributes. With the ability of creating zones, you should be able to setup your nodes groups to allow or not allow passwordless root ssh as before.

There are three commands to support zones:

* :doc:`mkzone </guides/admin-guides/references/man1/mkzone.1>` - creates the zones
* :doc:`chzone </guides/admin-guides/references/man1/chzone.1>` - changes a previously created zone
* :doc:`rmzone </guides/admin-guides/references/man1/rmzone.1>` - removes a zone

**Note**: It is highly recommended that you only use the zone commands for creating and maintaining your zones. They do a lot of maintaining of tables and directories for the zones when they are running.

