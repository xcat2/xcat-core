Select or Create an osimage Definition
======================================

Before creating an image on xCAT, the distro media should be prepared ahead. That can be ISOs or DVDs.

XCAT use 'copycds' command to create an image which will be available to install nodes. "copycds" will copy all contents of Distribution DVDs/ISOs or Service Pack DVDs/ISOs to a destination directory, and create several relevant osimage definitions by default.

If using an ISO, copy it to (or NFS mount it on) the management node, and then run: ::

    copycds <path>/<specific-distro>.iso
	
If using a DVD, put it in the DVD drive of the management node and run: ::

    copycds /dev/<dvd-drive-name> 

To see the list of osimages: ::

    lsdef -t osimage 
	
To see the attributes of a particular osimage: ::

    lsdef -t osimage <osimage-name>

Initially, some attributes of osimage are assigned default values by xCAT - they all can work correctly because the files or templates invoked by those attributes are shipped with xCAT by default. If you need to customize those attributes, refer to the next section :doc:`Customize osimage </guides/admin-guides/manage_clusters/ppc64le/diskful/customize_image/index>`
	
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

For ubuntu ppc64le, the initrd.gz shipped with the ISO does not support network booting. In order to install ubuntu with xCAT, you need to follow the steps below to complete the osimage definition.

* Download mini.iso from

  [ubuntu 14.04.1]: http://xcat.org/files/netboot/ubuntu14.04.1/ppc64el/mini.iso

  [ubuntu 14.04.2]: http://xcat.org/files/netboot/ubuntu14.04.2/ppc64el/mini.iso

  [ubuntu 14.04.3]: http://xcat.org/files/netboot/ubuntu14.04.3/ppc64el/mini.iso
  
  [ubuntu 14.04.4]: http://xcat.org/files/netboot/ubuntu14.04.4/ppc64el/mini.iso
  
  [ubuntu 16.04]: http://xcat.org/files/netboot/ubuntu16.04/ppc64el/mini.iso

* Mount mini.iso ::

    mkdir /tmp/iso
    mount -o loop mini.iso /tmp/iso

* Copy the netboot initrd.gz to osimage ::

    mkdir -p /install/<ubuntu-version>/ppc64el/install/netboot
    cp /tmp/iso/install/initrd.gz /install/<ubuntu-version>/ppc64el/installe/netboot

**[Below tips maybe helpful for you]** 

**[Tips 1]**

If this is the same distro version as what your management node uses, create a .repo file in /etc/yum.repos.d with contents similar to: ::

    [local-<os>-<arch>]
    name=xCAT local <os> <version>
    baseurl=file:/install/<os>/<arch>
    enabled=1
    gpgcheck=0
	
In this way, if you need to install some additional RPMs into your MN later, you can simply install them with ``yum``. Or if you are installing a software on your MN that depends some RPMs from this disto, those RPMs will be found and installed automatically.

**[Tips 2]**

You can create/modify an osimage definition easily based on the default osimage definition. The general steps are:

* lsdef -t osimage -z <os>-<arch>-install-compute   >   <filename>.stanza
* modify <filename>.stanza according to your requirements	
* cat <filename>.stanza| mkdef -z 

For example, if you need to change the osimage name to your favorite name, this command may be helpful: ::

    lsdef -t osimage -z rhels6.2-x86_64-install-compute | sed 's/^[^ ]\+:/mycomputeimage:/' | mkdef -z



