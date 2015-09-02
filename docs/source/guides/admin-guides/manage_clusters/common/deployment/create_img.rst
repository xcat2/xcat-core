Select or Create an osimage Definition
======================================

Before creating image by xCAT, distro media should be prepared ahead. That can be ISOs or DVDs.

XCAT use 'copycds' command to create image which will be available to install nodes. 'copycds' command copies the contents of distro from media to /install/<os>/<arch> on management node.

If using an ISO, copy it to (or NFS mount it on) the management node, and then run:
::
    copycds <path>/<specific-distro>.iso
	
If using a DVD, put it in the DVD drive of the management node and run:
::
    copycds /dev/<dvd-drive-name> 

The 'copycds' command automatically creates several osimage defintions in the database that can be used for node deployment. 
To see the list of osimages, run
::
    lsdef -t osimage 
	
To see the attributes of a particular osimage, run
::
    lsdef -t osimage <osimage-name>

Initially, some attributes of osimage is assigned to default value by xCAT, they all can work correctly, cause the files or templates invoked by those attributes are shipped with xCAT by default.	If need to customize those attribute, refer to next section "Customize osimage". 
	

**[Below tips maybe helpful for you]** 

**[Tips 1]**
If this is the same distro version as what your management node used, create a .repo file in /etc/yum.repos.d with content similar to:
::
    [local-<os>-<arch>]
    name=xCAT local <os> <version>
    baseurl=file:/install/<os>/<arch>
    enabled=1
    gpgcheck=0
	
In this way, if you need install some additional RPMs into your MN later, you can simply install them by yum. Or if you are installing a software on your MN that depends some RPMs from the this disto, those RPMs will be found and installed automatically.

**[Tips 2]**
If need to change osimage name to your favorite name, below statement maybe help:
::
    lsdef -t osimage -z rhels6.2-x86_64-install-compute | sed 's/^[^ ]\+:/mycomputeimage:/' | mkdef -z

	

