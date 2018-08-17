``rvitals`` - Remote Hardware Vitals
====================================

See :doc:`rvitals manpage </guides/admin-guides/references/man1/rvitals.1>` for more information.

Collecting runtime information from a running physical machine is an important part of system administration.  Data can be obtained from the service processor including temperature, voltage, cooling fans, etc.

Use the ``rvitals`` command to obtain this information.  ::

    rvitals <noderange> all

To only get the temperature information of machines in a particular noderange: ::

    rvitals <noderange> temp

