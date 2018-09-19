``rpower`` - Remote Power Control
=================================

See :doc:`rpower manpage </guides/admin-guides/references/man1/rpower.1>` for more information.

Use the ``rpower`` command to remotely power on and off a single server or a range of servers. ::

    rpower <noderange> on
    rpower <noderange> off

Other actions include:

   * To get the current power state of a server: ``rpower <noderange> state``
   * To boot/reboot a server: ``rpower <noderange> boot``
   * To hardware reset a server: ``rpower <noderange> reset``
