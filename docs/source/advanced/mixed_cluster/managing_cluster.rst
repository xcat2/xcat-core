Managing Clusters
=================

PPC64 MN deploying a System x86_64
----------------------------------

Provision x86_64 (bare metal)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

In order to provision x86_64 ipmi-based machines from xCAT management node (ppc64), there are a few required xCAT dependency RPMs that must be installed:

* ``elilo-xcat``
* ``xnba-undi``
* ``syslinux-xcat``

Install these RPMs using the following command: ::

    yum install elilo-xcat xnba-undi syslinux-xcat

On the ppc64 management node, obtain an x86_64 operating system ISO and add it into the xCAT osimage table by using the copycds command: ::

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
        chain=runcmd=bmcsetup,shell
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

Provision the node using the following commands: ::

    # The following prepares the kickstart file in /install/autoinst
    nodeset c910f04x42 osimage=rhels6.6-x86_64-install-compute

    # Tells the BIOS to network boot on the next power on
    rsetboot c910f04x42 net

    # Reboots the node
    rpower c910f04x42 boot

Provision x86_64 (diskless) 
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Troubleshooting
^^^^^^^^^^^^^^^

**Error:** The following Error message comes out when running nodeset: ::

    Error: Unable to find pxelinux.0 at /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0

**Resolution:** 

The syslinux network booting files are missing.  
Install the sylinux-xcat package provided in the xcat-deps repository: ``yum -y install syslinux-xcat``

.. _Building_a_Stateless_Image_of_a_Different_Architecture_or_OS:

Building a Stateless Image of a Different Architecture of OS
------------------------------------------------------------

**Note: The procedure below only works with xCAT 2.8.1 and later.**

The genimage command that builds a stateless image needs to be run on a node of the same architecture and OS major release level as the nodes that will ultimately be booted with this image. Usually the management node is running the same architecture and OS as the compute nodes, so you can run genimage directly on the management node. 

However, there are times when you may want to provision a different version of the OS or even a different OS. In this case, you would need to run genimage on a node installed with the target OS you want to provision.

The following example is for creating a stateless image of the same OS but different architecture. The management node is "xcatmn". It is assumed that the osimage objects are already defined on the management node for the compute profile. Also any pkglist files have already been created and are configured correctly in the osimage definition.

On xCAT management node, select the osimage you want to create. Although it is optional, we recommend you make a copy of the osimage, changing its name to a simpler name. For example: ::

	lsdef -t osimage -z rhels6.3-x86_64-netboot-compute | sed 's/^[^ ]\+:/mycomputeimage:/' | mkdef -z

Then dry-run the image to get the syntax for generating the image from another machine. ::

	genimage --dryrun mycomputeimage
	
The result will look like this: ::

	Generating image:
	cd /opt/xcat/share/xcat/netboot/rh
	./genimage -a x86_64 -o rhels6.3 -p compute --permission 755 --srcdir /install/rhels6.3/x86_64 --pkglist /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.pkglist --otherpkgdir /install/post/otherpkgs/rhels6.3/x86_64 --postinstall /opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall --rootimgdir /install/netboot/rhels6.3/x86_64/compute mycomputeimage

Login to a target node matching the correct architecture for the image we want to create and mount the /install directory from the xCAT management node: ::

	ssh <node>
	mkdir /install
	mount xcatmn:/install /install     # the mount needs to have read-write permission

Copy the executable and files in the netboot directory from the xCAT Management node: ::

	mkdir -p /opt/xcat/share/xcat/
	cd /opt/xcat/share/xcat/
	scp -r xcatmn:/opt/xcat/share/xcat/netboot .

If there is any osimage configuration file that is not in directory /opt/xcat/share/xcat or /install, copy the file from the management node to the same directory on this node. You could use lsdef -t osimage to check if there is any osimage configuration file that is not in directory /opt/xcat/share/xcat or /install.
	
Generate the image using the command printed out from the --dryrun. This is required since executing from a non xCAT management node will not be able to access the xCAT database to obtain the osimage information.
	
Now return to the management node and execute "packimage <osimage>" and continue provisioning your nodes.
