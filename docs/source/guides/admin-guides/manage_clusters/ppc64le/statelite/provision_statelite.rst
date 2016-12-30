Provision statelite
===================

Show current provmethod 
-----------------------

To determine the current provmethod of your node, run: ::

    lsdef <noderange> | provmethod

If an osimage name is specified for the provmethod, the osimage attribute settings stored in the osimage and linuximage table are used to locate the files for ``templates``, ``*pkglists``, ``syncfiles``, etc.

``Note``: syncfiles is not currently supported for statelite nodes. 

See attributes in the osimage, linuximage and nimimage tables. For example: ::

    tabdump -d osimage  
    tabdump -d linuximage 
    tabdump -d nimimage 

For a hierarchical cluster, the files must be placed under the site table installdir attribute path, usually ``/install`` directory, so they will be available when mounted on the service nodes. The site table installdir directory, is mounted or copied to the service nodes during the hierarchical install of compute nodes from the service nodes.

Generate default statelite image from distoro media
---------------------------------------------------

For our example, we are going to create a new compute node test osimage for ``rhels7.3`` on ``ppc64le``. This works fine for other archtectures ( e.g. ``x86_64``). Just substitute your architecture in the paths ( e.g. ``x86_64`` ). We will set up a test directory structure that we can use to create our image. Later we can just move that into production.

Use the copycds command to copy the appropriate iso image into the ``/install`` directory for xCAT. The copycds commands will copy the contents to ``/install/rhels7.3/<arch>``. For example: ::

    mkdir /iso
    cd /iso
    copycds RHEL-7.3-20161019.0-Server-ppc64le-dvd1.iso

The contents are copied into ``/install/rhels7.3/ppc64le/``

When copycds runs, it will automatically create default osimage names and paths in the osimage table and the linuximage table based on the os and architecture you are using. You can use these defaults as a starting point to create your own osimage definitions, or you can create your own image definition. We are going to use the statelite generated image for our example.

The configuration files pointed to by the attributes are the defaults shipped with xCAT. We will want to copy them to the ``/install`` directory, in our example the ``/install/test`` directory and modify them as needed. ::

    lsdef -t osimage -o rhels7.3-ppc64le-statelite-compute
    Object name: rhels7.3-ppc64le-statelite-compute
        exlist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.exlist
        imagetype=linux
        osarch=ppc64le
        osdistroname=rhels7.3-ppc64le
        osname=Linux
        osvers=rhels7.3
        otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le
        permission=755
        pkgdir=/install/rhels7.3/ppc64le
        pkglist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist
        postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall
        profile=compute
        provmethod=statelite
        rootimgdir=/install/netboot/rhels7.3/ppc64le/compute
        synclists=/install/custom/netboot/rh/compute.synclist

Customize your statelite osimage
--------------------------------

Create the osimage definition
`````````````````````````````

Setup your osimage/linuximage tables with new test image name, osvers,osarch, and paths to all the files for building and installing the node. So using the above generated ``rhels7.3-ppc64le-statelite-compute`` as an example, I am going to create my own image. The value for the provmethod attribute is osimage in my example.::

    mkdef -t osimage -o redhat7img \
    profile=compute imagetype=linux provmethod=statelite osarch=ppc64le osname=linux osvers=rhels7.3

Check your setup: ::

    lsdef -t osimage redhat7img
    Object name: redhat7img
        imagetype=linux
        osarch=ppc64le
        osname=linux
        osvers=rhels7.3
        profile=compute
        provmethod=statelite

Add the paths to your ``pkglist``, ``syncfile``, etc to the osimage definition, that you require. ``Note``, if you modify the files on the ``/opt/xcat/share/...`` path then copy to the appropriate ``/install/custom/...`` path. Remember all files must be under ``/install`` if using hierarchy (service nodes).

Copy the sample ``*list`` files and modify as needed: ::

    mkdir -p /install/test/netboot/rh
    cp -p /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist \
    /install/test/netboot/rh/compute.pkglist
    cp -p /opt/xcat/share/xcat/netboot/rh/compute.exlist \
    /install/test/netboot/rh/compute.exlist

    chdef -t osimage -o redhat7img \
        pkgdir=/install/rhels7.3/ppc64le \
        pkglist=/install/test/netboot/rh/compute.pkglist \
        exlist=/install/test/netboot/rh/compute.exlist \
        rootimgdir=/install/test/netboot/rh/ppc64le/compute

Check your setup: ::

    lsdef -t osimage -o redhat7img
    Object name: redhat7img
        exlist=/install/test/netboot/rh/compute.exlist
        imagetype=linux
        osarch=ppc64
        osname=linux
        osvers=rhels7.3
        pkgdir=/install/rhels7.3/ppc64le
        pkglist=/install/test/netboot/rh/compute.pkglist
        profile=compute
        provmethod=statelite
        rootimgdir=/install/test/netboot/rh/ppc64le/compute

Setup pkglists
``````````````

In the above example, you have defined your pkglist to be in ``/install/test/netboot/rh/compute.pkglist``.

Edit compute.pkglist and compute.exlist as needed. ::

    cd /install/test/netboot/rh/
    vi compute.pkglist compute.exlist

For example to add vi to be installed on the node, add the name of the vi rpm to compute.pkglist. Make sure nothing is excluded in compute.exlist that you need.

Install other specific packages
```````````````````````````````

Make the directory to hold additional rpms to install on the compute node. ::

    mkdir -p /install/test/post/otherpkgs/rh/ppc64le

Now copy all the additional OS rpms you want to install into ``/install/test/post/otherpkgs/rh/ppc64le``.

At first you need to create one text file which contains the complete list of files to include in the repository. The name of the text file is rpms.list and must be in ``/install/test/post/otherpkgs/rh/ppc64le`` directory. Create rpms.list: ::

    cd /install/test/post/otherpkgs/rh/ppc64le
    ls *.rpm > rpms.list

Then, run the following command to create the repodata for the newly-added packages: ::

    createrepo -i rpms.list /install/test/post/otherpkgs/rh/ppc64le

The ``createrepo`` command with -i rpms.list option will create the repository for the rpm packages listed in the rpms.list file. It won't destroy or affect the rpm packages that are in the same directory, but have been included into another repository.

Or, if you create a sub-directory to contain the rpm packages, for example, named other in ``/install/test/post/otherpkgs/rh/ppc64le``. Run the following command to create repodata for the directory ``/install/test/post/otherpkgs/rh/ppc64le``. ::

    createrepo /install/post/otherpkgs/<os>/<arch>/**other**

``Note``: Replace other with your real directory name.

Define the location of of your otherpkgs in your osimage: ::

    chdef -t osimage -o redhat7img \
    otherpkgdir=/install/test/post/otherpkgs/rh/ppc64le \
    otherpkglist=/install/test/netboot/rh/compute.otherpkgs.pkglist

There are examples under ``/opt/xcat/share/xcat/netboot/<platform>`` of typical ``*otherpkgs.pkglist`` files that can used as an example of the format.

Set up Post install scripts for statelite
`````````````````````````````````````````

The rules to create post install scripts for statelite image is the same as the rules for stateless/diskless install images.

There're two kinds of postscripts for statelite (also for stateless/diskless).

The first kind of postscript is executed at genimage time, it is executed again the image itself on the MN . It was setup in The postinstall file section before the image was generated.

The second kind of postscript is the script that runs on the node during node deployment time. During init.d timeframe, ``/etc/init.d/gettyset`` calls ``/opt/xcat/xcatdsklspost`` that is in the image. This script uses wget to get all the postscripts under ``mn:/install/postscripts`` and copy them to the ``/xcatpost`` directory on the node. It uses openssl or stunnel to connect to the xcatd on the mn to get all the postscript names for the node from the postscripts table. It then runs the postscripts for the node.

Setting up postinstall files (optional)
```````````````````````````````````````

Using postinstall files is optional. There are some examples shipped in ``/opt/xcat/share/xcat/netboot/<platform>``.

If you define a postinstall file to be used by genimage, then ::

    chdef -t osimage -o redhat7img postinstall=<your postinstall file path>.

Setting up Files to be synchronized on the nodes
````````````````````````````````````````````````

Setup the node to use your osimage
``````````````````````````````````
::
    chdef -t node -o node1 provmethod=redhat7img
    lsdef node1 | grep provmethod
        provmethod=redhat7img

Generate the image
------------------

Run the following command to generate the image based on your osimage named redhat6img. Adjust your genimage parameters to your architecture and network settings. See man genimage. ::

    genimage redhat7img

The genimage will create a default ``/etc/fstab`` in the image, for example: ::

    devpts  /dev/pts devpts   gid=5,mode=620 0 0
    tmpfs   /dev/shm tmpfs    defaults       0 0
    proc    /proc    proc     defaults       0 0
    sysfs   /sys     sysfs    defaults       0 0
    tmpfs   /tmp     tmpfs    defaults,size=10m             0 2
    tmpfs   /var/tmp     tmpfs    defaults,size=10m       0 2
    compute_x86_64    /   tmpfs   rw  0 1

If you want to change the defaults, on the management node, edit fstab in the image: ::

    cd /install/netboot/rhels6/x86_64/compute/rootimg/etc
    cp fstab fstab.ORIG
    vi fstab

Change these settings: ::

    proc /proc proc rw 0 0
    sysfs /sys sysfs rw 0 0
    devpts /dev/pts devpts rw,gid=5,mode=620 0 0
    #tmpfs /dev/shm tmpfs rw 0 0
    compute_x86_64 / tmpfs rw 0 1
    none /tmp tmpfs defaults,size=10m 0 2
    none /var/tmp tmpfs defaults,size=10m 0 2

``Note``: adding ``/tmp`` and ``/var/tmp`` to ``/etc/fstab`` is optional, most installations can simply use ``/``. It was documented her to show that you can restrict the size of filesystems, if you need to. The indicated values are just and example, and you may need much bigger filessystems, if running applications like OpenMPI.

Pack the image
--------------
::
    liteimg redhat7img

Boot the node
-------------
::
    rinstall node1 osimage=redhat7img

Switch to the RAMdisk based solution
------------------------------------

It is optional, if you want to use RAMdisk-based solution, follow this section.

Set rootfstype
``````````````

If you want the node to boot with a RAMdisk-based image instead of the NFS-base image, set the rootfstype attribute for the osimage to ``ramdisk``. For example: ::

    chdef -t osimage -o rhels6-ppc64-statelite-compute rootfstype=ramdisk

Run liteimg command
```````````````````

The ``liteimg`` command will modify your statelite image (the image that ``genimage`` just created) by creating a series of links. Once you are satisfied with your image contains what you want it to, run ``liteimg <osimagename>``: ::

    liteimg rhels6-ppc64-statelite-compute

For files with link options, the ``liteimg`` command creates two levels of indirection, so that files can be modified while in their image state as well as during runtime. For example, a file like ``$imageroot/etc/ntp.conf`` with link option in the litefile table, will have the following operations done to it:

In our case ``$imageroot`` is ``/install/netboot/rhels5.3/x86_64/compute/rootimg``

The ``liteimg`` script, for example, does the following to create the two levels of indirection. ::

    mkdir -p $imageroot/.default/etc
    mkdir -p $imageroot/.statelite/tmpfs/etc
    mv $imgroot/etc/ntp.conf $imgroot/.default/etc
    cd $imgroot/.statelite/tmpfs/etc
    ln -sf ../../../.default/etc/ntp.conf .
    cd $imgroot/etc
    ln -sf ../.statelite/tmpfs/etc/ntp.conf .

When finished, the original file will reside in ``$imgroot/.default/etc/ntp.conf``. ``$imgroot/etc/ntp.conf`` will link to ``$imgroot/.statelite/tmpfs/etc/ntp.conf`` which will in turn link to ``$imgroot/.default/etc/ntp.conf``.

But for files without link options, the ``liteimg`` command only creates clones in ``$imageroot/.default/`` directory, when the node is booting up, the mount command with ``--bind`` option will get the corresponding files from the ``litetree`` places or ``.default`` directory to the sysroot directory.

``Note``: If you make any changes to your litefile table after running ``liteimg`` then you will need to rerun ``liteimg`` again. This is because files and directories need to have the two levels of redirects created.

Boot the node
`````````````

Make sure you have set up all the attributes in your node definitions correctly following the node installation instructions corresponding to your hardware:

You can now deploy the node by running the following commmands: ::

    rinstall <noderange> 

This will create the necessary files in ``/tftpboot/etc`` for the node to boot correctly.
You can then use ``rcons`` or ``wcons`` to watch the node boot up.

Commands
--------

The following commands are in ``/opt/xcat/bin``: ::

    litefile <nodename> : Shows all the statelite files that are not to be taken from the base of the image.

    litetree <nodename> : Shows the NFS mount points for a node.

    liteimg <image name> : Creates a series of symbolic links in an image that is compatible with statelite booting.

    lslite -i <imagename> : Displays a summary of the statelite information defined for <imagename>.

    lslite <noderange> : Displays a summary of the statelite information defined for the <noderange> 

Statelite Directory Structure
-----------------------------

Each statelite image will have the following directories: ::

    /.statelite/tmpfs/
    /.default/
    /etc/init.d/statelite

All files with link options, which are symbolic links, will link to ``/.statelite/tmpfs``.

tmpfs files that are persistent link to ``/.statelite/persistent/<nodename>/``, ``/.statelite/persistent/<nodename>`` is the directory where the node's individual storage will be mounted to.

``/.default`` is where default files will be copied to from the image to tmpfs if the files are not found in the litetree hierarchy.

The noderes Table
`````````````````
``noderes.nfsserver`` attribute can be set for the NFSroot server. If this is not set, then the defaul is the Management Node.

``noderes.nfsdir`` can be set. If this is not set, the the default is ``/install``

Adding/updating software and files for the running nodes
--------------------------------------------------------

Make changes to the files which configured in the litefile table
````````````````````````````````````````````````````````````````

During the preparation or booting of node against statelite mode, there are specific processes to handle the files which configured in the litefile table. The following operations need to be done after made changes to the statelite files.

#. Run ``liteimg`` against the osimage and reboot the node : Added, removed or changed the entries in the litefile table.

#. Reboot the node :

    * Changed the location directory in the litetree table.
    * Changed the location directory in the statelite table.
    * Changed, removed the original files in the location of litetree or statelite table.

``Note``: Thing should not do:

    * When there are node running on the nfs-based statelite osimage, do not run the packimage against this osimage.

Make changes to the common files
````````````````````````````````

Because most of system files for the nodes are NFS mounted on the Management Node with read-only option, installing or updating software and files should be done to the image. The image is located under ``/install/netboot/<os>/<arch>/<profile>/rootimg`` directory.

To install or update an rpm, do the following:

   * Install the rpm package into rootimg ::

       rpm --root /install/netboot/<os>/<arch>/<profile>/rootimg -ivh rpm_name

   * Restart the software application on the nodes ::

       xdsh <noderange> <restart_this_software_command>

It is recommended to follow the section (Adding third party softeware) to add the new rpm to the otherpkgs.pkglist file, so that the rpm will get installed into the new image next time the image is rebuilt.

``Note``: The newly added rpms are not shown when running ``rpm -qa`` on the nodes although the rpm is installed. It will shown next time the node is rebooted.

To create or update a file for the nodes, just modify the file in the image and restart any application that uses the file.

For the ramdisk-based node, you need to reboot the node to take the changes.
