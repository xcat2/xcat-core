Using RPM (recommended)
=======================

**Support is only for RHEL 7.5 for Power LE (Power 9)**

If you want to install ``xCAT-openbmc-py`` on SN manually, please accoring **install xCAT-openbmc-py on MN** part. But if you hope xCAT could install it automatically, please config as **Install xCAT-openbmc-py on SN** part.

Install xCAT-openbmc-py on MN
-----------------------------

The following repositories should be configured on your Management Node (and Service Nodes).

   * RHEL 7.5 OS Repository
   * RHEL 7.5 Extras Repository
   * RHEL 7 EPEL Repo (https://fedoraproject.org/wiki/EPEL)
   * Fedora28 Repo (for ``gevent``, ``greenlet``)

#. Configure the MN/SN to the RHEL 7.5 OS Repo

#. Configure the MN/SN to the RHEL 7.5 Extras Repo

#. Configure the MN/SN to the EPEL Repo  (https://fedoraproject.org/wiki/EPEL) ::

    yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

#. Create a local Fedora28 Repo and Configure the MN/SN to the FC28 Repo

   Here's  an example to configure the Fedora 28 repo at ``/install/repos/fc28``

   #. Make the target repo directory on the MN: ::

        mkdir -p /install/repos/fc28/ppc64le/Packages

   #. Download the rpms from the Internet: ::

        cd /install/repos/fc28/ppc64le/Packages
        wget https://www.rpmfind.net/linux/fedora-secondary/releases/28/Everything/ppc64le/os/Packages/p/python2-gevent-1.2.2-2.fc28.ppc64le.rpm
        wget https://www.rpmfind.net/linux/fedora-secondary/releases/28/Everything/ppc64le/os/Packages/p/python2-greenlet-0.4.13-2.fc28.ppc64le.rpm

    #. Create a yum repo in that directory: ::

        cd /install/repos/fc28/ppc64le/
        createrepo .

#. Install ``xCAT-openbmc-py`` using ``yum``: ::

      yum install xCAT-openbmc-py

   **Note**: The install will fail if the dependencies cannot be met.

Install xCAT-openbmc-py on SN
-----------------------------

For all types of SN installation, need to create repo for ``gevent`` and ``greenlet`` and config ``otherpkglist`` of osimage on MN

#. Create the repo at ``otherpkgdir`` path as the example above, could run ``lsdef -t osimage <os>-<arch>-<install|netboot>-service`` to get the path ::

    # lsdef -t osimage rhels7.5-ppc64le-install-service | grep otherpkgdir
    otherpkgdir=/install/post/otherpkgs/rhels7.5/ppc64le

#. Configure ``otherpkglist`` of the current osimage ::

    # lsdef -t osimage rhels7.5-ppc64le-install-service | grep otherpkglist
    otherpkglist=/opt/xcat/share/xcat/install/rh/service.rhels7.ppc64le.otherpkgs.pkglist

    # cat /opt/xcat/share/xcat/install/rh/service.rhels7.ppc64le.otherpkgs.pkglist
    ...
    xcat/Packages/python2-gevent
    xcat/Packages/python2-greenlet
    xcat/xcat-core/xCAT-openbmc-py

Install on diskful SN by updatenode
```````````````````````````````````

If you have installed SN without ``xCAT-openbmc-py package``, could run updatenode to install it.

#. Sync epel repo and key file ::

    # rsync -v /etc/yum.repos.d/epel.repo root@10.3.17.17:/etc/yum.repos.d/
    # rsync -v /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 root@10.3.17.17:/etc/pki/rpm-gpg/

#. Update packages on SN ::

    # updatenode service -S

Install on diskful SN
`````````````````````

#. Configure ``synclists`` of osimage ::

    # lsdef -t osimage rhels7.5-ppc64le-install-service | grep synclists
    synclists=/install/custom/netboot/compute.synclist

    # cat /install/custom/netboot/compute.synclist
    ...
    /etc/yum.repos.d/epel.repo -> /etc/yum.repos.d/epel.repo
    /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 -> /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7

#. Install SN ::

    # rinstall service osimage=rhels7.5-ppc64le-install-service

Install on diskless SN
``````````````````````

#. Add epel online repo https://dl.fedoraproject.org/pub/epel/7/ppc64le  to ``pkgdir`` ::

    # lsdef -t osimage -o rhels7.5-ppc64le-netboot-service | grep pkgdir
    pkgdir=/install/rhels7.5/ppc64le,https://dl.fedoraproject.org/pub/epel/7/ppc64le

#. Install SN ::

    # genimage rhels7.5-ppc64le-netboot-service
    # packimage rhels7.5-ppc64le-netboot-service
    # rinstall service osimage=rhels7.5-ppc64le-netboot-service


