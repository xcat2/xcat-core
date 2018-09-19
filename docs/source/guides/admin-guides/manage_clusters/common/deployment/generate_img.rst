Generate Diskless Image
=======================

The ``copycds`` command copies the contents of the Linux media to ``/install/<os>/<arch>`` so that it will be available for installing nodes or creating diskless images.  After executing ``copycds``, there are several ``osimage`` definitions created by default.  Run ``tabdump osimage`` to view these images: ::

        tabdump osimage

The output should be similar to the following: ::

        "rhels7.1-ppc64le-install-compute",,"compute","linux",,"install",,"rhels7.1-ppc64le",,,"Linux","rhels7.1","ppc64le",,,,,,,,
        "rhels7.1-ppc64le-install-service",,"service","linux",,"install",,"rhels7.1-ppc64le",,,"Linux","rhels7.1","ppc64le",,,,,,,,
        "rhels7.1-ppc64le-stateful-mgmtnode",,"compute","linux",,"install",,"rhels7.1-ppc64le",,,"Linux","rhels7.1","ppc64le",,,,,,,,
        "rhels7.1-ppc64le-netboot-compute",,"compute","linux",,"netboot",,"rhels7.1-ppc64le",,,"Linux","rhels7.1","ppc64le",,,,,,,,

The ``netboot-compute`` is the default **diskless** osimage created rhels7.1 ppc64le.  Run ``genimage`` to generate a diskless image based on the "rhels7.1-ppc64le-netboot-compute" definition: ::

        genimage rhels7.1-ppc64le-netboot-compute

Before packing the diskless image, you have the opportunity to change any files in the image by changing to the ``rootimgdir`` and making modifications.  (e.g. ``/install/netboot/rhels7.1/ppc64le/compute/rootimg``).

However it's recommended that all changes to the image are made via post install scripts so that it's easily repeatable. Although, instead, we recommend that you make all changes to the image via your postinstall script, so that it is repeatable.  Refer to :doc:`/guides/admin-guides/manage_clusters/ppc64le/diskless/customize_image/pre_post_script` for more details.


Pack Diskless Image
===================

After you run ``genimage`` to create the image, you can go ahead to pack the image to create the ramdisk: ::

        packimage rhels7.1-ppc64le-netboot-compute

Export and Import Image
=======================

Overview
--------

Note: There is a current restriction that exported 2.7 xCAT images cannot be imported on 2.8 xCAT `<https://sourceforge.net/p/xcat/bugs/3813/>`_. This is no longer a restrictions, if you are running xCAT 2.8.3 or later.

We want to create a system of making xCAT images more portable so that they can be shared and prevent people from reinventing the wheel. While every install is unique there are some things that can be shared among different sites to make images more portable. In addition, creating a method like this allows us to create snap shots of images we may find useful to revert to in different situations.

Image exporting and importing are supported for stateful (diskful) and stateless (diskless) clusters.  The following documentation will show how to use :doc:`imgexport </guides/admin-guides/references/man1/imgexport.1>` to export images and :doc:`imgimport </guides/admin-guides/references/man1/imgimport.1>` to import images.


Exporting an image
------------------

1, The user has a working image and the image is defined in the osimage table and linuximage table.
  example: ::

        lsdef -t osimage myimage
        Object name: myimage
        exlist=/install/custom/netboot/sles/compute1.exlist
        imagetype=linux
        netdrivers=e1000
        osarch=ppc64le
        osname=Linux
        osvers=sles12
        otherpkgdir=/install/post/otherpkgs/sles12/ppc64
        otherpkglist=/install/custom/netboot/sles/compute1.otherpkgs.pkglist
        pkgdir=/install/sles11/ppc64le
        pkglist=/install/custom/netboot/sles/compute1.pkglist
        postinstall=/install/custom/netboot/sles/compute1.postinstall
        profile=compute1
        provmethod=netboot
        rootimgdir=/install/netboot/sles12/ppc64le/compute1
        synclists=/install/custom/netboot/sles/compute1.list
2, The user runs the imgexport command.
  example: ::

        imgexport myimage -p node1 -e /install/postscripts/myscript1 -e /install/postscripts/myscript2
        (-p and -e are optional)

A bundle file called myimage.tgz will be created under the current directory. The bundle file contains the ramdisk, boot kernel, the root image and all the configuration files for generating the image for a diskless cluster. For diskful, it contains the kickstart/autoyast configuration file. (see appendix). The -p flag puts the names of the postscripts for node1 into the image bundle. The -e flags put additional files into the bundle. In this case two postscripts myscript1 and myscript2 are included.
This image can now be used on other systems.

Importing an image
------------------

#. User downloads a image bundle file from somewhere. (Sumavi.com will be hosting many of these).
#. User runs the imgimport command.

  example: ::

        imgimport myimage.tgz -p group1
        (-p is optional)

This command fills out the osimage and linuximage tables, and populates file directories with appropriate files from the image bundle file such as ramdisk, boot kernel, root image, configuration files for diskless. Any additional files that come with the bundle file will also be put into the appropriate directories. If -p flag is specified, the postscript names that come with the image will be put the into the postscripts table for the given node or group.

Copy an image to a new image name on the MN
-------------------------------------------

Very often, the user wants to make a copy of an existing image on the same xCAT mn as a start point to make modifications. In this case, you can run imgexport first as described on chapter 2, then run imgimport with -f flag to change the profile name of the image. That way the image will be copied into a different directory on the same xCAT mn.

  example: ::

        imgimport myimage.tgz -p group1 -f compute2

Modify an image (optional)
--------------------------

Skip this section if you want to use the image as is.

1, The use can modify the image to fit his/her own need. The following can be modified.

* Modify .pkglist file to add or remove packages that are from the os distro

* Modify .otherpkgs.pkglist to add or remove packages from other sources. Refer to ``Using_Updatenode`` for details

* For diskful, modify the .tmpl file to change the kickstart/autoyast configuration

* Modify .synclist file to change the files that are going to be synchronized to the nodes

* Modify the postscripts table for the nodes to be deployed

* Modify the osimage and/or linuximage tables for the location of the source rpms and the rootimage location

2, Run genimage: ::

        genimage image_name

3, Run packimage: ::

        packimage image_name

Deploying nodes
---------------

You can change the provmethod of the node to the new image_name if different: ::

        chdef <noderange> provmethod=<image_name>
        nodeset <noderange> osimage=<image_name>

and the node is ready to deploy.

Appendix
--------

You can only export/import one image at a time. Each tarball will have the following simple structure: ::

        manifest.xml
        <files>
        extra/ (optional)

manifest.xml
~~~~~~~~~~~~

The manifest.xml will be analogous to an autoyast or windows unattend.xml file where it tells xCAT how to store the items. The following is an example for a diskless cluster: ::

        manifest.xml:

        <?xml version="1.0"?>
        <xcatimage>
          <exlist>/install/custom/netboot/sles/compute1.exlist</exlist>
          <extra>
            <dest>/install/postscripts</dest>
            <src>/install/postscripts/myscript1</src>
          </extra>
          <imagename>myimage</imagename>
          <imagetype>linux</imagetype>
          <kernel>/install/netboot/sles12/ppc64le/compute1/kernel</kernel>
          <netdrivers>e1000</netdrivers>
          <osarch>ppc64le</osarch>
          <osname>Linux</osname>
          <osvers>sles12</osvers>
          <otherpkgdir>/install/post/otherpkgs/sles12/ppc64</otherpkgdir>
          <otherpkglist>/install/custom/netboot/sles/compute1.otherpkgs.pkglist</otherpkglist>
          <pkgdir>/install/sles12/ppc64le</pkgdir>
          <pkglist>/install/custom/netboot/sles/compute1.pkglist</pkglist>
          <postbootscripts>my4,otherpkgs,my3,my4</postbootscripts>
          <postinstall>/install/custom/netboot/sles/compute1.postinstall</postinstall>
          <postscripts>syslog,remoteshell,my1,configrmcnode,syncfiles,my1,my2</postscripts>
          <profile>compute1</profile>
          <provmethod>netboot</provmethod>
          <ramdisk>/install/netboot/sles12/ppc64le/compute1/initrd-diskless.gz</ramdisk>
          <rootimg>/install/netboot/sles12/ppc64le/compute1/rootimg.gz</rootimg>
          <rootimgdir>/install/netboot/sles12/ppc64le/compute1</rootimgdir>
          <synclists>/install/custom/netboot/sles/compute1.list</synclists>
        </xcatimage>

In the above example, we have a directive of where the files came from and what needs to be processed.


Note that even though source destination information is included, all files that are standard will be copied to the appropriate place that xCAT thinks they should go.

Exported files
~~~~~~~~~~~~~~

The following files will be exported, assuming x is the profile name:

For diskful: ::

             x.pkglist
             x.otherpkgs.pkglist
             x.tmpl
             x.synclist


For diskless: ::

             kernel
             initrd.gz
             rootimg.gz
             x.pkglist
             x.otherpkgs.pkglist
             x.synclist
             x.postinstall
             x.exlist


Note: Although the postscripts names can be exported by using the -p flag. The postscripts themselves are not included in the bundle file by default. The use has to use -e flag to get them included one by one if needed.

