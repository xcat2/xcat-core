Quick Start Guide
=================
xCAT can be a comprehensive system to manage infrastructure elements in Data Center, bare-metal servers, switches, PDUs, and Operation System distributions. This quick start guide will instruct you to set up a xCAT system and manage an IPMI managed bare metal server with Red Hat-based distribution in 15 minutes. 

The steps below will be focused on RHEL7, however they should work for other distribution, such as CentOS, SLES, etc, details :doc:`Operating System & Hardware Support Matrix <../../overview/support_matrix>`

Prerequisites
-------------
Assume there are two servers named ``xcatmn.mydomain.com`` and ``cn1.mydomain.com``. 

    #. They are in the same subnet ``192.168.0.0``. 
    #. ``cn1.mydomain.com`` has BMC which ``xcatmn.mydomain.com`` can access it. 
    #. ``xcatmn.mydomain.com`` has Red Hat OS installed, and uses IP ``192.168.0.2``. 
    #. ``xcatmn.mydomain.com`` has access to internet. 
    #. ``cn1.mydomain.com`` BMC IP address is ``10.4.40.254``. 
    #. Prepare a full DVD for OS provision, and not a ``Live CD`` ISO, for this example, will use ``RHEL-7.6-20181010.0-Server-x86_64-dvd1.iso`` ISO, you can download it from Red Hat website.

All the following steps should be executed in ``xcatmn.mydomain.com``.

Prepare the Management Node ``xcatmn.mydomain.com``
```````````````````````````````````````````````````

#. Disable SELinux: ::

    echo 0 > /selinux/enforce
    sed -i 's/^SELINUX=.*$/SELINUX=disabled/' /etc/selinux/config

#. Set the hostname of ``xcatmn.mydomain.com``: ::

    hostname xcatmn.mydomain.com

#. Set the IP to STATIC in the ``/etc/sysconfig/network-scripts/ifcfg-<proc_nic>`` file

#. Update your ``/etc/resolv.conf`` with DNS settings and make sure that the node could visit ``github`` and ``xcat`` official website.

#. Configure any domain search strings and nameservers to the ``/etc/resolv.conf`` file

#. Add ``xcatmn`` into ``/etc/hosts``: ::

    192.168.0.2 xcatmn xcatmn.mydomain.com

#. Install xCAT: ::

    wget https://raw.githubusercontent.com/xcat2/xcat-core/master/xCAT-server/share/xcat/tools/go-xcat -O - >/tmp/go-xcat
    chmod +x /tmp/go-xcat
    go-xcat --yes install
    source /etc/profile.d/xcat.sh
   
#. Configure the system password for the root user on the compute nodes: ::

    chtab key=system passwd.username=root passwd.password=abc123

Stage 1 Add your first node and control it with out-of-band BMC interface
-------------------------------------------------------------------------

#. Define compute node ``cn1``: ::

    mkdef -t node cn1 --template x86_64-template ip=192.168.0.3 mac=42:3d:0a:05:27:0c bmc=10.4.40.254 bmcusername=USERID bmcpassword=PASSW0RD

#. Configure DNS: ::

    makehosts cn1 
    makedns -n

#. Check ``cn1`` Hardware Control:

``cn1`` power management: ::

    rpower cn1 on
    rpower cn1 state
    cn1: on

``cn1`` firmware information: ::

    rinv cn1 firm
    cn1: UEFI Version: 1.31 (TDE134EUS  2013/08/27)
    cn1: Backup UEFI Version: 1.00 (TDE112DUS )
    cn1: Backup IMM Version: 1.25 (1AOO26K 2012/02/23)
    cn1: BMC Firmware: 3.10 (1AOO48H 2013/08/22 18:49:44)

Stage 2 Provision a node and manage it with parallel shell
----------------------------------------------------------

#. In order to PXE boot, you need a DHCP server to hand out addresses and direct the booting system to the TFTP server where it can download the network boot files. Configure DHCP: ::

    makedhcp -n

#. Copy all contents of Distribution ISO into ``/install`` directory, create OS repository and osimage for OS provision: ::

    copycds RHEL-7.6-20181010.0-Server-x86_64-dvd1.iso

   After ``copycds``, the corresponding basic osimage will be generated automatically. And then you can list the new osimage name here. You can refer document to customize the package list or postscript for target compute nodes, but here just use the default one: ::

    lsdef -t osimage

#. Use ``xcatprobe`` to precheck xCAT management node ready for OS provision: ::

    xcatprobe xcatmn
    [mn]: Checking all xCAT daemons are running...                                      [ OK ]
    [mn]: Checking xcatd can receive command request...                                 [ OK ]
    [mn]: Checking 'site' table is configured...                                        [ OK ]
    [mn]: Checking provision network is configured...                                   [ OK ]
    [mn]: Checking 'passwd' table is configured...                                      [ OK ]
    [mn]: Checking important directories(installdir,tftpdir) are configured...          [ OK ]
    [mn]: Checking SELinux is disabled...                                               [ OK ]
    [mn]: Checking HTTP service is configured...                                        [ OK ]
    [mn]: Checking TFTP service is configured...                                        [ OK ]
    [mn]: Checking DNS service is configured...                                         [ OK ]
    [mn]: Checking DHCP service is configured...                                        [ OK ]
    ... ...
    [mn]: Checking dhcpd.leases file is less than 100M...                               [ OK ]
    =================================== SUMMARY ====================================
    [MN]: Checking on MN...                                                             [ OK ]

#. Start the Diskful OS Deployment: ::

    rinstall cn1 osimage=rhels7.6-x86_64-install-compute

#. Monitor Installation Process: ::

    makegocons cn1
    rcons cn1

   **Note**: The keystroke ``ctrl+e c .`` will disconnect you from the console.

   After 5-10 min verify provision status is ``booted``: ::
    
    lsdef cn1 -i status
    Object name: cn1
    status=booted

   Use ``xdsh`` to check ``cn1`` OS version, OS provision is successful: ::
    
    xdsh cn1 more /etc/*release
    cn1: ::::::::::::::
    cn1: /etc/os-release
    cn1: ::::::::::::::
    cn1: NAME="Red Hat Enterprise Linux Server"
    cn1: VERSION="7.6 (Maipo)"
    ... ...
