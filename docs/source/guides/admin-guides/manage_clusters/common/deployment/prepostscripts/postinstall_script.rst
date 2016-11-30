.. _Using-Postinstallscript-label:

=========================
Using postinstall scripts
=========================
While running ``genimage`` to generate diskless or statelite osimage, you may want to customize the root image after the package installation step. The ``postinstall`` attribute of the osimage definition provides a hook to run user specified script(s), in non-chroot mode, against the directory specified by ``rootimgdir`` attribute.

xCAT ships a default ``postinstall`` script for the diskless/statelite osimages that must be executed to ensure a successful provisioning of the OS: ::

  lsdef -t osimage -o rhels7.3-ppc64le-netboot-compute -i postinstall
  Object name: rhels7.3-ppc64le-netboot-compute
  postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall

Customizing the ``postinstall`` script, can be done by either one of the methods below:

 *  Append your own ``postinstall`` scripts ::

     chdef -t osimage -o <osimage> -p postinstall=/install/custom/postinstall/rh7/mypostscript

 *  Create your own ``postinstall`` script based on the default ``postinstall`` script ::

     cp /opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall /install/custom/postinstall/rh7/mypostscript
     # edit /install/custom/postinstall/rh7/mypostscript
     chdef -t osimage -o <osimage> postinstall=/install/custom/postinstall/rh7/mypostscript

Common questions about the usage of ``postinstall`` scripts:
------------------------------------------------------------

When do ``postinstall`` scripts run?
````````````````````````````````````

High level flow of ``genimage`` process:

a) install the packages specified by ``pkglist`` into ``rootimgdir`` directory
b) cumstomize the ``rootimgdir`` directory
c) generate the initrd based on the ``rootimgdir`` directory

The ``postinstall`` scripts are executed in step b).

Do ``postinstall`` scripts execute in chroot mode under ``rootimgdir`` directory?
`````````````````````````````````````````````````````````````````````````````````

No. Unlike postscripts and postbootscripts, the ``postinstall`` scripts are run in non-chroot environment, directly on the management node. In the postinstall scripts, all the paths of the directories and files are based on  ``/`` of the managememnt node. To reference inside the ``rootimgdir``, use the ``$IMG_ROOTIMGDIR`` environment variable, exported by ``genimage``.

What are some of the environment variables available to my customized ``postinstall`` scripts?
``````````````````````````````````````````````````````````````````````````````````````````````

Environment variables, available to be used in the ``postinstall`` scripts are listed in ``postinstall`` attribute section of :doc:`linuximage </guides/admin-guides/references/man5/linuximage.5>`
