Using RPM (recommended)
=======================

.. note:: Supported only on RHEL 7.5 for POWER9

.. note:: In a herarchical environment ``xCAT-openbmc-py`` must be installed on both Management and Service nodes. On Service node ``xCAT-openbmc-py`` can be installed directly by following instructions in **Install xCAT-openbmc-py on MN**, or ``xCAT-openbmc-py`` can be installed on Service node from Management node by following instructions in **Install xCAT-openbmc-py on SN from MN**

Install xCAT-openbmc-py on MN
-----------------------------

The following repositories should be configured on your Management Node.

   * RHEL 7.5 OS repository
   * RHEL 7.5 Extras repository
   * RHEL 7 EPEL repository (https://fedoraproject.org/wiki/EPEL)
   * Fedora28 repository (for ``gevent`` and ``greenlet``)

#. Configure RHEL 7.5 OS repository 

#. Configure RHEL 7.5 Extras repository

#. Configure EPEL repository ::

    yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

#. Create a local Fedora28 repository and configure the MN to the FC28 Repo

   Here's an example to configure the Fedora 28 repository at ``/install/repos/fc28``

   #. Make the target repository directory on the MN: ::

        mkdir -p /install/repos/fc28/ppc64le/Packages

   #. Download the rpms: ::

        cd /install/repos/fc28/ppc64le/Packages
        wget https://www.rpmfind.net/linux/fedora-secondary/releases/28/Everything/ppc64le/os/Packages/p/python2-gevent-1.2.2-2.fc28.ppc64le.rpm
        wget https://www.rpmfind.net/linux/fedora-secondary/releases/28/Everything/ppc64le/os/Packages/p/python2-greenlet-0.4.13-2.fc28.ppc64le.rpm

   #. Create a repository in that directory: ::

        cd /install/repos/fc28/ppc64le/
        createrepo .

   #. Create a repo file ``/etc/yum.repos.d/fc28.repo`` and set its contents: ::

        [fc28]
        name=Fedora28 yum repository for gevent and greenlet
        baseurl=file:///install/repos/fc28/ppc64le/
        enabled=1
        gpgcheck=0
        
#. Install ``xCAT-openbmc-py`` : ::

      yum install xCAT-openbmc-py

Install xCAT-openbmc-py on SN from MN
-------------------------------------

.. attention:: Instructions below assume Service node has access to the Internet. If not, a local EPEL repository would need to be configured on the Management node, similar to the RHEL Extras repository.

#. Copy ``Packages`` directory containing ``gevent`` and ``greenlet`` rpms from ``/install/repos/fc28/ppc64le`` to the directory pointed to by ``otherpkgdir`` attribute of the osimage. ::

    # Display the directory of otherpkgdir
    lsdef -t osimage rhels7.5-ppc64le-install-service -i otherpkgdir -c

    # Create Packages directory
    mkdir /install/post/otherpkgs/rhels7.5-alternate/ppc64le/xcat/Packages

    # Copy rpms
    cp /install/repos/fc28/ppc64le/Packages/*.rpm /install/post/otherpkgs/rhels7.5-alternate/ppc64le/xcat/Packages

    

#. Configure ``otherpkglist`` attribute of the osimage ::

    chdef -t osimage rhels7.5-ppc64le-install-service otherpkglist=/opt/xcat/share/xcat/install/rh/service.rhels7.ppc64le.otherpkgs.pkglist

#. Add the following entries to the contents of ``/opt/xcat/share/xcat/install/rh/service.rhels7.ppc64le.otherpkgs.pkglist`` ::

    ...
    xcat/Packages/python2-gevent
    xcat/Packages/python2-greenlet
    xcat/xcat-core/xCAT-openbmc-py

#. Choose one of the 3 methods below to complete the installation

Install on diskful SN using updatenode
``````````````````````````````````````

If SN was installed without ``xCAT-openbmc-py`` package, ``updatenode`` can be used to install that package.

#. Sync EPEL repository and key file ::

    rsync -v /etc/yum.repos.d/epel.repo root@<SN>:/etc/yum.repos.d/
    rsync -v /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 root@<SN>:/etc/pki/rpm-gpg/

#. Update packages on SN ::

    updatenode <SN> -S

Install on diskful SN using rinstall
````````````````````````````````````

#. Configure ``synclists`` attribute of osimage ::

    chdef -t osimage rhels7.5-ppc64le-install-service synclists=/install/custom/netboot/compute.synclist

#. Add the following to the contents of ``/install/custom/netboot/compute.synclist`` ::

    ...
    /etc/yum.repos.d/epel.repo -> /etc/yum.repos.d/epel.repo
    /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 -> /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

#. Install SN ::

    rinstall <SN> osimage=rhels7.5-ppc64le-install-service

Install on diskless SN using rinstall
`````````````````````````````````````

#. Add EPEL online repository https://dl.fedoraproject.org/pub/epel/7/ppc64le to ``pkgdir`` attribute of osimage::

    chdef -t osimage -o rhels7.5-ppc64le-netboot-service -p pkgdir=https://dl.fedoraproject.org/pub/epel/7/ppc64le

#. Install diskless SN ::

    genimage rhels7.5-ppc64le-netboot-service
    packimage rhels7.5-ppc64le-netboot-service
    rinstall <SN> osimage=rhels7.5-ppc64le-netboot-service


