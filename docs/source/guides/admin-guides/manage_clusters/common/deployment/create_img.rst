Select or Create an osimage Definition
======================================

Before creating image by xCAT, distro media should be prepared ahead. That can be ISOs or DVDs.

XCAT use 'copycds' command to create image which will be available to install nodes. "copycds" will copy all contents of Distribution DVDs/ISOs or Service Pack DVDs/ISOs to a destination directory, and create several relevant osimage definitions by default.

If using an ISO, copy it to (or NFS mount it on) the management node, and then run: ::

    copycds <path>/<specific-distro>.iso
	
If using a DVD, put it in the DVD drive of the management node and run: ::

    copycds /dev/<dvd-drive-name> 

To see the list of osimages: ::

    lsdef -t osimage 
	
To see the attributes of a particular osimage: ::

    lsdef -t osimage <osimage-name>

Initially, some attributes of osimage is assigned to default value by xCAT, they all can work correctly, cause the files or templates invoked by those attributes are shipped with xCAT by default.	If need to customize those attribute, refer to next section :doc:`Customize osimage </guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/index>`
	
Below is an example of osimage definitions created by ``copycds``: ::

	# lsdef -t osimage
	rhels7.2-ppc64le-install-compute  (osimage)
	rhels7.2-ppc64le-install-service  (osimage)
	rhels7.2-ppc64le-netboot-compute  (osimage)
	rhels7.2-ppc64le-stateful-mgmtnode  (osimage)

In these osimage definitions shown above 

* **<os>-<arch>-install-compute** is the default osimage definition used for diskful installation
* **<os>-<arch>-netboot-compute** is the default osimage definition used for diskless installation
* **<os>-<arch>-install-service** is the default osimage definition used for service node deployment which shall be used in hierarchical environment

**Note**: There are more things needed for **ubuntu ppc64le** osimages:

For ubuntu ppc64le, the shipped initrd.gz within ISO is not supported to do network booting. In order to install ubuntu with xCAT, you need to follow the steps below to complete the osimage definition.

* Download mini.iso from

  [ubuntu 14.04.1]: http://ports.ubuntu.com/ubuntu-ports/dists/$(lsb_release-sc)/main/installer-ppc64el/current/images/netboot/

  [ubuntu 14.04.2]: http://ports.ubuntu.com/ubuntu-ports/dists/trusty-updates/main/installer-ppc64el/current/images/utopic-netboot/

  [ubuntu 14.04.3]: http://ports.ubuntu.com/ubuntu-ports/dists/trusty-updates/main/installer-ppc64el/current/images/vivid-netboot/

* Mount mini.iso ::

    mkdir /tmp/iso
    mount -o loop mini.iso /tmp/iso

* Copy the netboot initrd.gz to osimage ::

    mkdir -p /install/<ubuntu-version>/ppc64el/install/netboot
    cp /tmp/iso/install/initrd.gz /install/<ubuntu-version>/ppc64el/installe/netboot

**[Below tips maybe helpful for you]** 

**[Tips 1]**

If this is the same distro version as what your management node used, create a .repo file in /etc/yum.repos.d with content similar to: ::

    [local-<os>-<arch>]
    name=xCAT local <os> <version>
    baseurl=file:/install/<os>/<arch>
    enabled=1
    gpgcheck=0
	
In this way, if you need install some additional RPMs into your MN later, you can simply install them by yum. Or if you are installing a software on your MN that depends some RPMs from the this disto, those RPMs will be found and installed automatically.

**[Tips 2]**

Sometime you can create/modify a osimage definition easily based on the default osimage definition. the general steps can be:

* lsdef -t osimage -z <os>-<arch>-install-compute   >   <filename>.stanza
* modify <filename>.stanza depending on your requirement	
* cat <filename>.stanza| mkdef -z 

For example, if need to change osimage name to your favorite name, below statement maybe helpful: ::

    lsdef -t osimage -z rhels6.2-x86_64-install-compute | sed 's/^[^ ]\+:/mycomputeimage:/' | mkdef -z



