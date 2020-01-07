``reventlog`` - Remote Event Log of Service Processors
======================================================

See :doc:`reventlog manpage </guides/admin-guides/references/man1/reventlog.1>` for more information.

The ``reventlog`` command can be used to display and clear event log information on the service processor, or Baseboard Management Controller (BMC), of a physical machine. OpenBMC based servers need the `IBM OpenBMC tool <http://www.ibm.com/support/customercare/sas/f/lopdiags/scaleOutLCdebugtool.html#OpenBMC>`_ to obtain more detailed logging messages.

For example, to display all event log entries for node  ``cn5``: ::

    reventlog cn5 

To clear all event log entries for node  ``cn5``: ::

    reventlog cn5 clear
