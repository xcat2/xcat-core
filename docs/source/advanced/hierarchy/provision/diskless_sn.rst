.. _setup_service_node_stateless_label:

Diskless (Stateless) Installation
=================================

.. note:: The stateless Service Node is not supported in Ubunti hierarchy cluster. For Ubunti, skip this section.

If you want, your Service Nodes can be stateless (diskless). The Service Node
must contain not only the OS, but also the xCAT software and its dependencies.
In addition, a number of files are added to the Service Node to support the
PostgreSQL, or MySQL database access from the Service Node to the Management
node, and ssh access to the nodes that the Service Nodes services.
The following sections explain how to accomplish this.


Build the Service Node Diskless Image
-------------------------------------

This section assumes you can build the stateless image on the management node because the Service Nodes are the same OS and architecture as the management node. If this is not the case, you need to build the image on a machine that matches the Service Node's OS architecture.

* Create an osimage definition.

When you run ``copycds``, xCAT will only create a Service Node stateful osimage definitions for that distribution. For a stateless Service Node osimage, you may create it from a stateless Compute Node osimage definition.  ::

    lsdef -t osimage | grep -i netboot
    rhels7.3-ppc64le-netboot-compute  (osimage)

    mkdef -t osimage -o rhels7.3-ppc64le-netboot-service \
               --template rhels7.3-ppc64le-netboot-compute \
               profile=service provmethod=netboot postscripts=servicenode

    lsdef -t osimage rhels7.3-ppc64le-netboot-service
    Object name: rhels7.3-ppc64le-netboot-service
        exlist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.exlist
        imagetype=linux
        osarch=ppc64le
        osdistroname=rhels7.3-ppc64le
        osname=Linux
        osvers=rhels7.3
        otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le
        pkgdir=/install/rhels7.3/ppc64le
        pkglist=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.pkglist
        postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall
        postscripts=servicenode
        profile=service
        provmethod=netboot
        rootimgdir=/install/netboot/rhels7.3/ppc64le/compute

* Configure mandatory attributes for Service Node osimage definition.

  The following attributes must be modified to suitable value: ::

    exlist
    otherpkglist
    pkglist
    postinstall
    rootimgdir

#. Create the exlist, pkglist and otherpkglist file.

  xCAT ships a basic requirements lists that will create a fully functional Service Node. However, you may want to customize your service node by adding additional operating system packages or modifying the files excluded by the exclude list. Check the below files to see if it meets your needs. ::

    cd /opt/xcat/share/xcat/netboot/rh/
    view service.rhels7.ppc64le.pkglist
    view service.rhels7.ppc64le.otherpkgs.pkglist
    view service.rhels7.ppc64le.exlist

  If you would like to change any of these files, copy them to a custom
  directory. This can be any directory you choose, but we recommend that you
  keep it /install somewhere. A good location is something like ``/install/custom/netboot/<osimage>``.

  ::

    export OSIMAGE_DIR=/install/custom/netboot/rhels7.3-ppc64le-netboot-service

    mkdir -p $OSIMAGE_DIR

    cp /opt/xcat/share/xcat/netboot/rh/service.rhels7.ppc64le.pkglist $OSIMAGE_DIR
    cp /opt/xcat/share/xcat/netboot/rh/service.rhels7.ppc64le.otherpkgs.pkglist $OSIMAGE_DIR
    cp /opt/xcat/share/xcat/netboot/rh/service.rhels7.ppc64le.exlist $OSIMAGE_DIR

  And make sure that your ``otherpkgs.pkglist`` file has the following entries:

  ::

    xcat/xcat-core/xCATsn
    xcat/xcat-dep/<os>/<arch>/conserver-xcat
    xcat/xcat-dep/<os>/<arch>/perl-Net-Telnet
    xcat/xcat-dep/<os>/<arch>/perl-Expect

  For example, for the osimage *rhels7.3-ppc64le-netboot-service*: ::

    xcat/xcat-core/xCATsn
    xcat/xcat-dep/rh7/ppc64le/conserver-xcat
    xcat/xcat-dep/rh7/ppc64le/perl-Net-Telnet
    xcat/xcat-dep/rh7/ppc64le/perl-Expect

.. note:: You will be installing the xCAT Service Node RPM ``xCATsn`` on the Service Node, not the xCAT Management Node RPM.  Do not install both.

#. Create the postinstall script.

  xCAT ships a default postinstall script for stateless Service Node. You may also choose to create an appropriate /etc/fstab file in your
  Service Node image. :

  ::

    export OSIMAGE_DIR=/install/custom/netboot/rhels7.3-ppc64le-netboot-service
    cp /opt/xcat/share/xcat/netboot/rh/service.rhels7.ppc64le.postinstall $OSIMAGE_DIR

    vi $OSIMAGE_DIR/service.rhels7.ppc64le.postinstall
      # uncomment the sample fstab lines and change as needed:
      proc /proc proc rw 0 0
      sysfs /sys sysfs rw 0 0
      devpts /dev/pts devpts rw,gid=5,mode=620 0 0
      service_ppc64le / tmpfs rw 0 1
      none /tmp tmpfs defaults,size=10m 0 2
      none /var/tmp tmpfs defaults,size=10m 0 2

#. Modify the Service Node osimage definition with given attributes.

  ::

    export OSIMAGE_DIR=/install/custom/netboot/rhels7.3-ppc64le-netboot-service
    chdef -t osimage -o rhels7.3-ppc64le-netboot-service \
               exlist=$OSIMAGE_DIR/service.rhels7.ppc64le.exlist \
               otherpkglist=$OSIMAGE_DIR/service.rhels7.ppc64le.otherpkgs.pkglist \
               pkglist=$OSIMAGE_DIR/service.rhels7.ppc64le.pkglist \
               postinstall=$OSIMAGE_DIR/service.rhels7.ppc64le.postinstall \
               rootimgdir=$OSIMAGE_DIR/service

    lsdef -t osimage -l rhels7.3-ppc64le-netboot-service
    Object name: rhels7.3-ppc64le-netboot-service
        exlist=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service.rhels7.ppc64le.exlist
        imagetype=linux
        osarch=ppc64le
        osdistroname=rhels7.3-ppc64le
        osname=Linux
        osvers=rhels7.3
        otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le
        otherpkglist=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service.rhels7.ppc64le.otherpkgs.pkglist
        pkgdir=/install/rhels7.3/ppc64le
        pkglist=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service.rhels7.ppc64le.pkglist
        postinstall=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service.rhels7.ppc64le.postinstall
        postscripts=servicenode
        profile=service
        provmethod=netboot
        rootimgdir=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service


  While you are here, if you'd like, you can do the same for your Service Node
  images, creating custom files and new custom osimage definitions as you need
  to.

* Make your xCAT software available for otherpkgs processing

  Option 1:

  If you downloaded xCAT to your management node for installation, place a
  copy of your ``xcat-core`` and ``xcat-dep`` in your ``otherpkgdir`` directory ::

    lsdef -t osimage -o rhels7.3-ppc64le-netboot-service -i otherpkgdir
    Object name: rhels7.3-ppc64le-netboot-service
        otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le
    cd /install/post/otherpkgs/rhels7.3/ppc64le
    mkdir xcat
    cd xcat
    cp -Rp <current location of xcat-core>/xcat-core
    cp -Rp <current location of xcat-dep>/xcat-dep

  Option 2:

  If you installed your management node directly from the online
  repository, you will need to download the ``xcat-core`` and ``xcat-dep`` tarballs

  - From http://xcat.org/download.html, download the ``xcat-core`` and ``xcat-dep`` tarball files.
    Copy these into a subdirectory in the ``otherpkgdir`` directory.

    ::

      lsdef -t osimage -o rhels7.3-ppc64le-netboot-service -i otherpkgdir
      Object name: rhels7.3-ppc64le-netboot-service
          otherpkgdir=/install/post/otherpkgs/rhels7.3/ppc64le

      cd /install/post/otherpkgs/rhels7.3/ppc64le
      mkdir xcat
      cd xcat

      # copy the <xcat-core> and <xcat-deb> tarballs here

      # extract the tarballs
      tar -jxvf <xcat-core>.tar.bz2
      tar -jxvf <xcat-dep>.tar.bz2

* Run image generation for your osimage definition:

  ::

      genimage rhels7.3-ppc64le-netboot-service

* Prevent DHCP from starting up until xcatd has had a chance to configure it:

  ::

    export OSIMAGE_ROOT=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service
    chroot $OSIMAGE_ROOT/rootimg chkconfig dhcpd off
    chroot $OSIMAGE_ROOT/rootimg chkconfig dhcrelay off

* IF using NFS hybrid mode, export /install read-only in Service Node image:

  ::

    export OSIMAGE_ROOT=/install/custom/netboot/rhels7.3-ppc64le-netboot-service/service
    cd $OSIMAGE_ROOT/rootimg/etc
    echo '/install *(ro,no_root_squash,sync,fsid=13)' >exports

* Pack the image for your osimage definition:

  ::

    packimage rhels7.3-ppc64le-netboot-service

Install Service Nodes
------------------------

  ::

    rinstall service osimage=rhels7.3-ppc64le-netboot-service

  Watch the installation progress using either wcons or rcons:

  ::

    wcons service     # make sure DISPLAY is set to your X server/VNC or
    rcons <node_name>
    tail -f /var/log/messages


Enable localdisk for stateless Service Node (Optional)
------------------------------------------------------

If you want, your can leverage local disk to contain some directories during the
stateless nodes running. And you can customize the osimage definition to achieve it.
For Service Node, it is recommended to put below directories
on local disk. ::

    #/install         (Not required when using shared /install directory)
    #/tftpboot        (Not required when using shared /tftpboot directory)
    /var/log
    /tmp

The following section explains how to accomplish this.

*  Change the Service Node osimage definition to enable ``localdisk``

::

    #create a partition file to partition and mount the disk
    export OSIMAGE=rhels7.3-ppc64le-netboot-service
    cat<<EOF > /install/custom/netboot/$OSIMAGE/partitionfile
    enable=yes
    enablepart=yes

    [disk]
    dev=/dev/sda
    clear=yes
    parts=10,50

    [localspace]
    dev=/dev/sda2
    fstype=ext4

    [swapspace]
    dev=/dev/sda1
    EOF

    #add the partition file to Service Node osimage definition and configure ``policy`` table
    chdef -t osimage -o $OSIMAGE partitionfile=/install/custom/netboot/$OSIMAGE/partitionfile
    chtab priority=7.1 policy.commands=getpartition policy.rule=allow

    #define files or directories which are required to be put on local disk
    #chtab litefile.image=$OSIMAGE litefile.file=/install/ litefile.options=localdisk
    #chtab litefile.image=$OSIMAGE litefile.file=/tftpboot/ litefile.options=localdisk
    chtab litefile.image=$OSIMAGE litefile.file=/var/log/ litefile.options=localdisk
    chtab litefile.image=$OSIMAGE litefile.file=/tmp/ litefile.options=localdisk

* Run image generation and repacking for your osimage definition:

  ::

    genimage rhels7.3-ppc64le-netboot-service
    packimage rhels7.3-ppc64le-netboot-service


.. note:: ``enablepart=yes`` in partition file will partition the local disk at every boot. If you want to preserve the contents on local disk at next boot, change to ``enablepart=no`` after the initial provision.

For more information on ``localdisk`` option, refer to :ref:`setup_localdisk_label`

Update Service Node Stateless Image
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To update the xCAT software in the image at a later time:

  * Download the updated xcat-core and xcat-dep tarballs and place them in
    your osimage's otherpkgdir xcat directory as you did above.
  * Generate and repack the image and reboot your Service Node.
  * Run image generation for your osimage definition.

  ::

    genimage "<osimagename>"
    packimage "<osimagename>"
    rinstall service osimage="<osimagename>"

.. note:: The Service Nodes are set up as NFS-root servers for the compute nodes.
 Any time changes are made to any compute image on the mgmt node it will be
 necessary to sync all changes to all Service Nodes. In our case the
 ``/install`` directory is mounted on the servicenodes, so the update to the
 compute node image is automatically available.

