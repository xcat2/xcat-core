.. _setup_service_node_stateless_label:

Diskless (Stateless) Installation
=================================

**Note: The stateless Service Node is not supported in ubuntu hierarchy cluster. For ubuntu, skip this section.**

If you want, your Service Nodes can be stateless (diskless). The Service Node
must contain not only the OS, but also the xCAT software and its dependencies.
In addition, a number of files are added to the Service Node to support the
PostgreSQL, or MySQL database access from the Service Node to the Management
node, and ssh access to the nodes that the Service Nodes services.
The following sections explain how to accomplish this.


Build the Service Node Diskless Image
-------------------------------------

This section assumes you can build the stateless image on the management node because the Service Nodes are the same OS and architecture as the management node. If this is not the case, you need to build the image on a machine that matches the Service Node's OS architecture.

* Create an osimage definition. When you run ``copycds``, xCAT will create a Service Node osimage definitions for that distribution. For a stateless
  Service Node, use the ``*-netboot-service`` definition.  ::

    # lsdef -t osimage | grep -i service
    rhels6.4-ppc64-install-service  (osimage)
    rhels6.4-ppc64-netboot-service  (osimage)  <================
    rhels6.4-ppc64-statelite-service  (osimage)

    # lsdef -t osimage -l rhels6.3-ppc64-netboot-service
    Object name: rhels6.3-ppc64-netboot-service
        exlist=/opt/xcat/share/xcat/netboot/rh/service.exlist
        imagetype=linux
        osarch=ppc64
        osdistroname=rhels6.3-ppc64
        osname=Linux
        osvers=rhels6.3
        otherpkgdir=/install/post/otherpkgs/rhels6.3/ppc64
        otherpkglist=/opt/xcat/share/xcat/netboot/rh/service.rhels6.ppc64.otherpkgs.pkglist
        pkgdir=/install/rhels6.3/ppc64
        pkglist=/opt/xcat/share/xcat/netboot/rh/service.rhels6.ppc64.pkglist
        postinstall=/opt/xcat/share/xcat/netboot/rh/service.rhels6.ppc64.postinstall
        profile=service
        provmethod=netboot
        rootimgdir=/install/netboot/rhels6.3/ppc64/service

* You can check the Service Node packaging to see if it has all the rpms you require. We ship a basic requirements lists that will create a fully functional Service Node. However, you may want to customize your service node by adding additional operating system packages or modifying the files excluded by the exclude list. View the files referenced by the osimage pkglist, otherpkglist and exlist attributes: ::

    cd /opt/xcat/share/xcat/netboot/rh/
    view service.rhels6.ppc64.pkglist
    view service.rhels6.ppc64.otherpkgs.pkglist
    view service.exlist

  If you would like to change any of these files, copy them to a custom
  directory. This can be any directory you choose, but we recommend that you
  keep it /install somewhere. A good location is something like
  ``/install/custom/netboot/<os>/service``. Make sure that your
  ``otherpkgs.pkglist`` file as an entry for

  ::

    xcat/xcat-core/xCATsn

  This is required to install the xCAT Service Node function into your image.

  You may also choose to create an appropriate /etc/fstab file in your
  Service Node image. Copy the script referenced by the postinstall
  attribute to your directory and modify it as you would like:

  ::

    cp /opt/xcat/share/xcat/netboot/rh/service.rhels6.ppc64.postinstall
    /install/custom/netboot/rh
    vi /install/custom/netboot/rh
    # uncomment the sample fstab lines and change as needed:
    proc /proc proc rw 0 0
    sysfs /sys sysfs rw 0 0
    devpts /dev/pts devpts rw,gid=5,mode=620 0 0
    service_x86_64 / tmpfs rw 0 1
    none /tmp tmpfs defaults,size=10m 0 2
    none /var/tmp tmpfs defaults,size=10m 0 2

  After modifying the files, you will need to update the osimage definition to
  reference these files. We recommend creating a new osimage definition for
  your custom image: ::

    lsdef -t osimage -l rhels6.3-ppc64-netboot-service -z > /tmp/myservice.def
    vi /tmp/myservice.def
    # change the name of the osimage definition
    # change any attributes that now need to reference your custom files
    # change the rootimgdir attribute replacing 'service'
    with a name to match your new osimage definition
    cat /tmp/msyservice.def | mkdef -z

  While you are here, if you'd like, you can do the same for your compute node
  images, creating custom files and new custom osimage definitions as you need
  to.

* Make your xCAT software available for otherpkgs processing

* If you downloaded xCAT to your management node for installation, place a
  copy of your xcat-core and xcat-dep in your otherpkgdir directory ::

    lsdef -t osimage -o rhels6.3-ppc64-netboot-service -i otherpkgdir
    Object name: rhels6.3-ppc64-netboot-service
    otherpkgdir=/install/post/otherpkgs/rhels6.3/ppc64
    cd /install/post/otherpkgs/rhels6.3/ppc64
    mkdir xcat
    cd xcat
    cp -Rp <current location of xcat-core>/xcat-core
    cp -Rp <current location of xcat-dep>/xcat-dep

* If you installed your management node directly from the online
  repository, you will need to download the ``xcat-core`` and ``xcat-dep`` tarballs

  - From http://xcat.org/download.html, download the ``xcat-core`` and ``xcat-dep`` tarball files.  
    Copy these into a subdirectory in the ``otherpkgdir`` directory. 

    ::

      lsdef -t osimage -o rhels6.3-ppc64-netboot-service -i otherpkgdir
      Object name: rhels6.3-ppc64-netboot-service
          otherpkgdir=/install/post/otherpkgs/rhels6.3/ppc64
          
      cd /install/post/otherpkgs/rhels6.3/ppc64
      mkdir xcat
      cd xcat
      
      # copy the <xcat-core> and <xcat-deb> tarballs here
      
      # extract the tarballs
      tar -jxvf <xcat-core>.tar.bz2
      tar -jxvf <xcat-dep>.tar.bz2

* Run image generation for your osimage definition:

  ::

      genimage rhels6.3-ppc64-netboot-service

* Prevent DHCP from starting up until xcatd has had a chance to configure it:

  ::

    chroot /install/netboot/rhels6.3/ppc64/service/rootimg chkconfig dhcpd off
    chroot /install/netboot/rhels6.3/ppc64/service/rootimg chkconfig dhcrelay off

* IF using NFS hybrid mode, export /install read-only in Service Node image:

  ::

    cd /install/netboot/rhels6.3/ppc64/service/rootimg/etc
    echo '/install *(ro,no_root_squash,sync,fsid=13)' >exports

* Pack the image for your osimage definition:

  ::

    packimage rhels6.3-ppc64-netboot-service

* Set the node status to ready for netboot using your osimage definition and
  your 'service' nodegroup:

  ::

    nodeset service osimage=rhels6.3-ppc64-netboot-service

*  To diskless boot the Service Nodes

  ::

    rnetboot service

Update Service Node Stateless Image
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To update the xCAT software in the image at a later time:

  * Download the updated xcat-core and xcat-dep tarballs and place them in
    your osimage's otherpkgdir xcat directory as you did above.
  * Generate and repack the image and reboot your Service Node.
  * Run image generation for your osimage definition.

  ::

    genimage rhels6.3-ppc64-netboot-service
    packimage rhels6.3-ppc64-netboot-service
    nodeset service osimage=rhels6.3-ppc64-netboot-service
    rnetboot service

Note: The Service Nodes are set up as NFS-root servers for the compute nodes.
Any time changes are made to any compute image on the mgmt node it will be
necessary to sync all changes to all Service Nodes. In our case the
``/install`` directory is mounted on the servicenodes, so the update to the
compute node image is automatically available.

Monitor install and boot
------------------------

::

    wcons service # make sure DISPLAY is set to your X server/VNC or
    rcons <one-node-at-a-time> # or do rcons for each node
    tail -f /var/log/messages

