``rcons`` - Remote Console
==========================

See :doc:`rcons manpage </guides/admin-guides/references/man1/rcons.1>` for more information.

Most enterprise servers do not have video adapters installed with the machine and often do not provide a method for attaching a physical monitor/keyboard/mouse to get the display output.  For this purpose xCAT can assist the system administrator to view the console over a "Serial-over-LAN" (SOL) connection through the BMC.

Configure the correct console management by modifying the node definition:

    * For OpenPOWER, **IPMI** managed server: ::

        chdef -t node -o <noderange> cons=ipmi

    * For OpenPOWER, **OpenBMC** managed servers: ::

        chdef -t node -o <noderange> cons=openbmc

Open a console to ``compute1``: ::

    rcons compute1

.. note:: The keystroke ``ctrl+e c .`` will disconnect you from the console.


Troubleshooting
---------------

General
```````

``xCAT`` has been integrated with 3 kinds of console server service, they are

    - `conserver <http://www.conserver.com/>`_ **[Deprecated]**
    - `goconserver <https://github.com/xcat2/goconserver/>`_
    - `confluent <https://github.com/xcat2/confluent/>`_

``rcons`` command relies on one of them. The ``conserver`` and ``goconserver``
packages should have been installed with xCAT as they are part of the xCAT
dependency packages. If you want to try ``confluent``,
see :doc:`confluent server </advanced/confluent/server/confluent_server>`.

For systemd based systems, ``goconserver`` is used by default. If you are
having problems seeing the console, try the following.

   #. Make sure ``goconserver`` is configured by running ``makegocons``.

   #. Check if ``goconserver`` is up and running ::

      systemctl status goconserver.service

   #. If ``goconserver`` is not running, start the service using: ::

      systemctl start goconserver.service

   #. Try ``makegocons -q [<node>]`` to verify if the node has been registered.

   #. Invoke the console again: ``rcons <node>``

More details for goconserver, see :doc:`goconserver documentation </advanced/goconserver/index>`.

**[Deprecated]** If ``conserver`` is used, try the following.

   #. Make sure ``conserver`` is configured by running ``makeconservercf``.

   #. Check if ``conserver`` is up and running ::

         [sysvinit] service conserver status
         [systemd] systemctl status conserver.service

   #. If ``conserver`` is not running, start the service using: ::

         [sysvinit] service conserver start
         [systemd] systemctl start conserver.service

   #. Invoke the console again: ``rcons <node>``
