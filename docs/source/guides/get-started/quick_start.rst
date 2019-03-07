Quick Start Guide
=================

This quick start guide is a 15-minute procedure to set up an xCAT cluster on Red Hat-based distribution. These examples are based on IPMI managed baremetal servers.

Prerequisites
-------------
Assume there are two servers named ``xcatmn1`` and ``cn1``. They are in the same subnet ``192.168.0.0``, their BMCs are in the same network ``10.0.0.0``. ``xcatmn1`` has Red Hat OS installed, and uses IP ``192.168.0.2``. ``xcatmn1`` has access to ``xcat.org``. ``cn1`` BMC IP address is ``10.4.40.254``. Prepare a full DVD for OS provision, and not a ``Live CD`` ISO, for this example, use ``RHEL-7.6-20181010.0-Server-x86_64-dvd1.iso`` ISO.

All the following steps should be executed in ``xcatmn1``.

Prepare the Management Node ``xcatmn1``
```````````````````````````````````````

#. Disable SELinux: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

#. Set the hostname of ``xcatmn.cluster.com``: ::

    hostname xcatmn.cluster.com

#. Set the IP to STATIC in the ``/etc/sysconfig/network-scripts/ifcfg-eth0`` file

#. Configure any domain search strings and nameservers to the ``/etc/resolv.conf`` file

#. Add ``xcatmn`` into ``/etc/hosts``: ::

    192.168.0.2 xcatmn xcatmn.cluster.com

#. Install xCAT: ::

    wget https://raw.githubusercontent.com/xcat2/xcat-core/master/xCAT-server/share/xcat/tools/go-xcat -O - >/tmp/go-xcat
    chmod +x /tmp/go-xcat
    go-xcat --yes install
    source /etc/profile.d/xcat.sh

Stage 1 Enable Hardware Control
-------------------------------

#. Define compute node ``cn1``: ::

    chdef cn1 bmc=10.4.40.254 mgt=ipmi groups=all bmcusername=USERID bmcpassword=PASSW0RD

#. Check ``cn1`` Power state: ::

    rpower cn1 state
    cn1: on

Stage 2 Deploy Compute Node
---------------------------

#. Configure DNS: ::

    chdef cn1 ip=192.168.0.3
    makehosts cn1
    makedns -n
    
#. Configure DHCP: ::

    makedhcp -n
    makedhcp -a

#. Create osimage: ::

    copycds RHEL-7.6-20181010.0-Server-x86_64-dvd1.iso
    lsdef -t osimage

#. Start the Diskful OS Deployment: ::

    chdef cn1 mgt=ipmi netboot=xnba arch=x86_64 mac=34:40:b5:b9:d6:4f
    rinstall cn1 osimage=rhels7.6-x86_64-install-compute

#. Monitor Installation Process: ::

    chdef cn1 serialport=0 serialspeed=115200 cons=ipmi
    makegocons cn1
    rcons cn1

   **Note**: The keystroke ``ctrl+e c .`` will disconnect you from the console.
