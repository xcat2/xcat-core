Provision statelite
===================

Show current provisioning method 
--------------------------------

To determine the current provisioning method of your node, execute: ::

    lsdef <noderange> -i provmethod

``Note``: syncfiles is not currently supported for statelite nodes. 

Generate default statelite image from distoro media
---------------------------------------------------

In this example, we are going to create a new compute node osimage for ``rhels7.3`` on ``ppc64le``. We will set up a test directory structure that we can use to create our image. Later we can just move that into production.

Use the copycds command to copy the appropriate iso image into the ``/install`` directory for xCAT. The copycds commands will copy the contents to ``/install/rhels7.3/<arch>``. For example: ::

    copycds RHEL-7.3-20161019.0-Server-ppc64le-dvd1.iso

The contents are copied into ``/install/rhels7.3/ppc64le/``

The configuration files pointed to by the attributes are the defaults shipped with xCAT. We will want to copy them to the ``/install`` directory, in our example the ``/install/test`` directory and modify them as needed. 

Statelite Directory Structure
-----------------------------

Each statelite image will have the following directories: ::

    /.statelite/tmpfs/
    /.default/
    /etc/init.d/statelite

All files with link options, which are symbolic links, will link to ``/.statelite/tmpfs``.

tmpfs files that are persistent link to ``/.statelite/persistent/<nodename>/``, ``/.statelite/persistent/<nodename>`` is the directory where the node's individual storage will be mounted to.

``/.default`` is where default files will be copied to from the image to tmpfs if the files are not found in the litetree hierarchy.

Customize your statelite osimage
--------------------------------

Create the osimage definition
`````````````````````````````

Setup your osimage/linuximage tables with new test image name, osvers,osarch, and paths to all the files for building and installing the node. So using the above generated ``rhels7.3-ppc64le-statelite-compute`` as an example, I am going to create my own image. The value for the provisioning method attribute is osimage in my example.::

    mkdef rhels7.3-custom-statelite -u profile=compute provmethod=statelite

Check your setup: ::
     
    lsdef -t osimage rhels7.3-custom-statelite

Customize the paths to your ``pkglist``, ``syncfile``, etc to the osimage definition, that you require. ``Note``, if you modify the files on the ``/opt/xcat/share/...`` path then copy to the appropriate ``/install/custom/...`` path. Remember all files must be under ``/install`` if using hierarchy (service nodes).

Copy the sample ``*list`` files and modify as needed: ::

    mkdir -p /install/test/netboot/rh
    cp -p /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist \
    /install/test/netboot/rh/compute.rhels7.ppc64le.pkglist
    cp -p /opt/xcat/share/xcat/netboot/rh/compute.exlist \
    /install/test/netboot/rh/compute.exlist

    chdef -t osimage -o rhels7.3-custom-statelite \
        pkgdir=/install/rhels7.3/ppc64le \
        pkglist=/install/test/netboot/rh/compute.rhels7.ppc64le.pkglist \
        exlist=/install/test/netboot/rh/compute.exlist \
        rootimgdir=/install/test/netboot/rh/ppc64le/compute

Setup pkglists
``````````````

In the above example, you have defined your pkglist to be in ``/install/test/netboot/rh/compute.rhels7.ppc64le.pkglist``.

Edit ``compute.rhels7.ppc64le.pkglist`` and ``compute.exlist`` as needed. ::

    vi /install/test/netboot/rh/compute.rhels7.ppc64le.pkglist
    vi /install/test/netboot/rh/compute.exlist

Make sure nothing is excluded in compute.exlist that you need.

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

    chdef -t osimage -o rhels7.3-custom-statelite \
    otherpkgdir=/install/test/post/otherpkgs/rh/ppc64le \
    otherpkglist=/install/test/netboot/rh/compute.otherpkgs.pkglist

There are examples under ``/opt/xcat/share/xcat/netboot/<platform>`` of typical ``*otherpkgs.pkglist`` files that can used as an example of the format.

Set up Post scripts for statelite
`````````````````````````````````

The rules to create post install scripts for statelite image is the same as the rules for stateless/diskless install images.

There're two kinds of postscripts for statelite (also for stateless/diskless).

The first kind of postscript is executed at genimage time, it is executed again the image itself on the MN . It was setup in The postinstall file section before the image was generated.

The second kind of postscript is the script that runs on the node during node deployment time. During init.d timeframe, ``/etc/init.d/gettyset`` calls ``/opt/xcat/xcatdsklspost`` that is in the image. This script uses wget to get all the postscripts under ``mn:/install/postscripts`` and copy them to the ``/xcatpost`` directory on the node. It uses openssl or stunnel to connect to the xcatd on the mn to get all the postscript names for the node from the postscripts table. It then runs the postscripts for the node.

Setting up postinstall files (optional)
```````````````````````````````````````

Using postinstall files is optional. There are some examples shipped in ``/opt/xcat/share/xcat/netboot/<platform>``.

If you define a postinstall file to be used by genimage, then ::

    chdef -t osimage -o rhels7.3-custom-statelite postinstall=<your postinstall file path>.

Generate the image
------------------

Run the following command to generate the image based on your osimage named ``rhels7.3-custom-statelite``. Adjust your genimage parameters to your architecture and network settings. See man genimage. ::

    genimage rhels7.3-custom-statelite

The genimage will create a default ``/etc/fstab`` in the image, if you want to change the defaults, on the management node, edit fstab in the image: ::

    cd /install/netboot/rhels7/ppc64le/compute/rootimg/etc
    cp fstab fstab.ORIG
    vi fstab

``Note``: adding ``/tmp`` and ``/var/tmp`` to ``/etc/fstab`` is optional, most installations can simply use ``/``. It was documented her to show that you can restrict the size of filesystems, if you need to. The indicated values are just and example, and you may need much bigger filessystems, if running applications like OpenMPI.

Pack the image
--------------

Execute liteimg ::

    liteimg rhels7.3-custom-statelite

Boot the statelite node
-----------------------

Execute ``rinstall`` ::

    rinstall node1 osimage=rhels7.3-custom-statelite

Switch to the RAMdisk based solution
------------------------------------

It is optional, if you want to use RAMdisk-based solution, follow this section.

Set rootfstype
``````````````

If you want the node to boot with a RAMdisk-based image instead of the NFS-base image, set the rootfstype attribute for the osimage to ``ramdisk``. For example: ::

    chdef -t osimage -o rhels7.3-custom-statelite rootfstype=ramdisk

Run liteimg command
```````````````````

The ``liteimg`` command will modify your statelite image (the image that ``genimage`` just created) by creating a series of links. Once you are satisfied with your image contains what you want it to, run ``liteimg <osimagename>``: ::

    liteimg rhels7.3-custom-statelite

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

Boot the statelite node
```````````````````````

Make sure you have set up all the attributes in your node definitions correctly following the node installation instructions corresponding to your hardware:

You can now deploy the node by running the following commmands: ::

    rinstall <noderange> 

You can then use ``rcons`` or ``wcons`` to watch the node boot up.

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
