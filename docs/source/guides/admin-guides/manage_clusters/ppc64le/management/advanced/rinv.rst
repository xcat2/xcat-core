``rinv`` - Remote Hardware Inventory
====================================

See :doc:`rinv manpage </guides/admin-guides/references/man1/rinv.1>` for more information.

Use ``rinv`` command to remotely obtain inventory information of a physical machine. This will help to distinguish one machine from another and aid in mapping the model type and/or serial number of a machine with its host name.

To get all the hardware information for node ``cn1``: ::

    rinv cn1 all

To get just the firmware information for ``cn1``: ::

    rinv cn1 firm

