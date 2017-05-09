``rcons`` - Remote Console
==========================

See :doc:`rcons manpage </guides/admin-guides/references/man1/rcons.1>` for more information.

Most enterprise servers do not have video adapters installed with the machine and often do not provide a method for attaching a physical monitor/keyboard/mouse to get the display output.  For this purpose xCAT can assist the system administrator to view the console over a "Serial-over-LAN" (SOL) connection through the BMC.

Configure the correct console management by modifying the node definition:

    * For OpenPower, **IPMI** managed server: ::

        chdef -t node -o <noderange> cons=ipmi

    * For OpenPower, **OpenBMC** managed servers: ::
 
        chdef -t node -o <noderange> cons=openbmc

Open a console to ``compute1``: ::

    rcons compute1

**Note:** The keystroke ``ctrl+E C .`` will disconnect you from the console.


Troubleshooting
---------------

General
```````

The xCAT ``rcons`` command relies on conserver (http://www.conserver.com/).  The ``conserver`` package should have been installed with xCAT as it's part of the xCAT dependency package.  If you are having problems seeing the console, try the following. 

   #. Make sure ``conserver`` is configured by running ``makeconservercf``.

   #. Check if ``conserver`` is up and running ::

         [sysvinit] service conserver status
         [systemd] systemctl status conserver.service

   #. If ``conserver`` is not running, start the service using: :: 

         [sysvinit] service conserver start 
         [systemd] systemctl start conserver.service

   #. After this, try invoking the console again:  ``rcons <node>``


OpenBMC Spcific
```````````````

   #. For OpenBMC managed servers, the root user must be able to ssh passwordless to the BMC for the ``rcons`` function to work.  

      Copy the ``/root/.ssh/id_rsa.pub`` public key to the BMC's ``~/.ssh/authorized_keys`` file.
