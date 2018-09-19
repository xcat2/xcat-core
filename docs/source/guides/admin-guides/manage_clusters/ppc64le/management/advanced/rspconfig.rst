``rspconfig`` - Remote Configuration of Service Processors
==========================================================

See :doc:`rspconfig manpage </guides/admin-guides/references/man1/rspconfig.1>` for more information.

The ``rspconfig`` command can be used to configure the service processor, or Baseboard Management Controller (BMC), of a physical machine.

For example, to turn on SNMP alerts for node  ``cn5``: ::

    rspconfig cn5 alert=on
