Cumulus OS Upgrade
==================

The Cumulus OS on the ONIE switches can be upgraded using one of the following methods:

Full Install
------------

Perform a full install from the ``.bin`` file of the new Cumulus Linux OS version, using ONIE.

.. important:: Make sure you back up all your data and configuration files as the binary install will erase all previous configuration.

#. Place the binary image under ``/install`` on the xCAT MN node.

   In this example, IP=172.21.253.37 is the IP on the Management Node. ::

      mkdir -p /install/onie/
      cp cumulus-linux-3.4.1.bin /install/onie/

#. Invoke the upgrade on the switches using :doc:`xdsh </guides/admin-guides/references/man1/xdsh.1>`: ::

      xdsh switch1 "/usr/cumulus/bin/onie-install -a -f -i \
      http://172.21.253.37/install/onie/cumulus-linux-3.4.1.bin && reboot"

   .. attention:: The full upgrade process may run 30 minutes or longer.

#. After upgrading, the license should be installed, see :ref:`Activate the License <activate-the-license>` for details.

#. Restore your data and configuration files on the switch.



Update Changed Packages
-----------------------

This is the preferred method for upgrading the switch OS for incremental OS updates.

Create Local Mirror
```````````````````

If the switches do not have access to the public Internet, you can create a local mirror of the Cumulus Linux repo.

#. Create a local mirror on the Management Node: ::

    mkdir -p /install/mirror/cumulus
    cd /install/mirror/cumulus
    wget -m --no-parent http://repo3.cumulusnetworks.com/repo/

#. Create a ``sources.list`` file to point to the local repo on the Management node.  In this example, IP=172.21.253.37 is the IP on the Management Node. ::

    # cat /tmp/sources.list
    deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3 cumulus upstream
    deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3 cumulus upstream

    deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-security-updates cumulus upstream
    deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-security-updates cumulus upstream

    deb     http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-updates cumulus upstream
    deb-src http://172.21.253.37/install/mirror/cumulus/repo3.cumulusnetworks.com/repo CumulusLinux-3-updates cumulus upstream


#. Distribute the ``sources.list`` file to your switches using :doc:`xdcp </guides/admin-guides/references/man1/xdcp.1>`. ::

    xdcp switch1 /tmp/sources.list  /etc/apt/sources.list

Invoke the Update
`````````````````

#. Use xCAT :doc:`xdsh </guides/admin-guides/references/man1/xdsh.1>` to invoke the update: ::

    #
    # A reboot may be needed after the upgrade
    #
    xdsh switch1 'apt-get update && apt-get upgrade && reboot'

#. Check in ``/etc/os-release`` file to verify that the OS has been upgraded.



