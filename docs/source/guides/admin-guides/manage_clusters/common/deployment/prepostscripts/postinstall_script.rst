.. _Using-Postinstallscript-label:

Using Postinstall Script
------------------------
While generating the rootimage directory for diskless or statelite osimage with ``genimage``, you may want to customize the rootimage after the package installation. The `postinstall` attribute of the osimage definition provides a hook to run user specicied script(s) against the rootimage directory in non-chrooted mode.

xCAT ships the default postinstall scripts for the diskless/statelite osimages created with ``copycds``, for example ::

  >lsdef -t osimage -o rhels7.3-ppc64le-netboot-compute -i postinstall
  Object name: rhels7.3-ppc64le-netboot-compute
  postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall

Notice: All the operations inside the default postinstall scripts are mandatory for the osimage provision. If you want to customize the postinstall script for an osimage, you should make sure the contents of default postinstall script are included. This can be done in either of the following ways:

 1. Append your own postinstall scripts by ``chdef -t osimage -o <osimage> -p postinstall=<comma seperated list of full paths to postinstall scipts>``
 2. Create your own postinstall script based on the default postinstall script, then ``chdef -t osimage -o <osimage> postinstall=<customized postinstall script>``

The following are some key points in Q/A format, that will help you understand the usage of postinstall scripts:

When will the postinstall scripts run?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In general, the brief workflow of ``genimage`` is:

a) install the packages specified in package list under rootimage directory
b) cumstomizing the rootimage directory, such as system configuration file generation/modification 
c) generate the initrd based on the rootimage directory

The postinstall scripts are run in step b).

Are postinstall scripts run in chrooted mode under rootimage directory?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

No. Unlike postscripts & postbootscripts, the postinstall scripts are run in non-chrooted mode. In the postinstall scripts, all the paths of the directories and files are based on the "/" of the managememnt node. You can change the working directory to rootimage directory with ``cd $IMG_ROOTIMGDIR``. "$IMG_ROOTIMGDIR" is an environment variable exported by genimage containing the full path of the rootimage directory on management node.

What are some of the environment variables available to my customized scripts?
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Besides "$IMG_ROOTIMGDIR" mentioned above, ``genimage`` exports a batch of environment variables while postinstall scripts are run, which can be used in your customized scipts. ::

  IMG_ARCH(The architecture of the osimage, such as "ppc64le","x86_64"),
  IMG_NAME(The name of the osimage, such as "rhels7.3-ppc64le-netboot-compute"),
  IMG_OSVER(The os release of the osimage, such as "rhels7.3","sles11.4"),
  IMG_KERNELVERSION(the "kernelver" attribute of the osimage),
  IMG_PROFILE(the profile of the osimage, such as "service","compute"),
  IMG_PKGLIST(the "pkglist" attribute of the osimage),
  IMG_PKGDIR(the "pkgdir" attribute of the osimage),
  IMG_OTHERPKGLIST(the "otherpkglist" attribute of the osimage),
  IMG_OTHERPKGDIR(the "otherpkgdir" attribute of the osimage),
  IMG_ROOTIMGDIR(the "rootimgdir" attribute of the osimage)

