Provision x86 Diskful
=====================

In order to provision x86_64 ipmi-based machines from Power-based xCAT management node, there are a few required xCAT dependency RPMs that must be installed:

* ``elilo-xcat``
* ``xnba-undi``
* ``syslinux-xcat``

Install these RPMs using the following command: ::

    yum install elilo-xcat xnba-undi syslinux-xcat

On the Power-based management node, obtain an x86_64 operating system ISO and add it into the xCAT osimage table by using the ``copycds`` command: ::

    copycds /tmp/RHEL-6.6-20140926.0-Server-x86_64-dvd1.iso

Create a node definition for the x86_64 compute node, here is a sample: ::

    lsdef -z c910f04x42
    # <xCAT data object stanza file>

    c910f04x42:
        objtype=node
        arch=x86_64
        bmc=10.4.42.254
        bmcpassword=PASSW0RD
        bmcusername=USERID
        cons=ipmi
        groups=all
        initrd=xcat/osimage/rhels6.6-x86_64-install-compute/initrd.img
        installnic=mac
        kcmdline=quiet repo=http://!myipfn!:80/install/rhels6.6/x86_64 ks=http://!myipfn!:80/install/autoinst/c910f04x42 ksdevice=34:40:b5:b9:c0:18  cmdline  console=tty0 console=ttyS0,115200n8r
        kernel=xcat/osimage/rhels6.6-x86_64-install-compute/vmlinuz
        mac=34:40:b5:b9:c0:18
        mgt=ipmi
        netboot=xnba
        nodetype=osi
        os=rhels6.6
        profile=compute
        provmethod=rhels6.6-x86_64-install-compute
        serialflow=hard
        serialport=0
        serialspeed=115200

Verify the genesis packages:

* **[RHEL/SLES]**: ``rpm -qa | grep -i genesis``

* **[Ubuntu]**: ``dpkg -l | grep -i genesis``

If missing, install the packages ``xCAT-genesis-base`` and ``xCAT-genesis-scripts`` from ``xcat-deps`` repository and run ``mknb <arch>`` to create the genesis network boot root image.


Provision the node using the following commands: ::

    # The following prepares the boot files in /install and /tftpboot
    nodeset c910f04x42 osimage=rhels6.6-x86_64-install-compute

    # Tells the BIOS to network boot on the next power on
    rsetboot c910f04x42 net

    # Reboots the node
    rpower c910f04x42 boot

