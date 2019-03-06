Quick Start Guide
=================

This quickstart guide is a 15-minute procedure to set up an xCAT cluster on Red Hat-based distribution. The focus and examples are based on IPMI managed baremetal servers.

Prerequisites
-------------
Assume there are 2 servers named ``xcatmn1`` and ``cn1``. They are in the same subnet ``192.168.0.0``, their BMC is in the same network ``10.0.0.0``. ``xcatmn1`` is with redhat OS installed, ``192.168.0.2`` is its ip, it can be used for xCAT management IP. ``xcatmn1`` has access to ``xcat.org``. ``10.4.40.254`` is ``cn1`` BMC ip address.

All the following steps should be executed in ``xcatmn1``.

Prepare the Management Node ``xcatmn1``
```````````````````````````````````````

#. Disable SELinux: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

#. To set the hostname of ``xcatmn.cluster.com``: ::

    hostname xcatmn.cluster.com

#. setting the IP to STATIC in the ``/etc/sysconfig/network-scripts/ifcfg-eth0`` file

#. Configure any domain search strings and nameservers to the ``/etc/resolv.conf`` file

#. Add ``xcatmn`` into ``/etc/hosts``: ::

    192.168.0.2 xcatmn xcatmn.cluster.com

#. Installing xCAT: ::

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

#. Monitor Installing Process: ::

    chdef cn1 serialport=0 serialspeed=115200 cons=ipmi
    makegocons cn1
    rcons cn1
