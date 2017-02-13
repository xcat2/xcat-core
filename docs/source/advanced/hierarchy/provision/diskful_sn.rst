
.. _setup_service_node_stateful_label:

Diskful (Stateful) Installation
===============================

Any cluster using statelite compute nodes must use a stateful (diskful) Service Nodes.

**Note:** All xCAT Service Nodes must be at the exact same xCAT version as the xCAT Management Node.

Configure ``otherpkgdir`` and ``otherpkglist`` for service node osimage
----------------------------------------------------------------------

 * Create a subdirectory ``xcat`` under a path specified by ``otherpkgdir`` attribute of the service node os image, selected during the :doc:`../define_service_nodes` step. 

   For example, for osimage *rhels7-x86_64-install-service* ::

    [root@fs4 xcat]# lsdef -t osimage rhels7-x86_64-install-service -i otherpkgdir
       Object name: rhels7-x86_64-install-service
          otherpkgdir=/install/post/otherpkgs/rhels7/x86_64
    [root@fs4 xcat]# mkdir -p /install/post/otherpkgs/rhels7/x86_64/xcat

 * Download or copy `xcat-core` and `xcat-dep` .bz2 files into that `xcat` directory ::

    wget https://xcat.org/files/xcat/xcat-core/<version>_Linux/xcat-core/xcat-core-<version>-linux.tar.bz2
    wget https://xcat.org/files/xcat/xcat-dep/<version>_Linux/xcat-dep-<version>-linux.tar.bz2

 * untar the `xcat-core` and `xcat-dep` .bz2 files ::

    cd /install/post/otherpkgs/<os>/<arch>/xcat
    tar jxvf core-rpms-snap.tar.bz2
    tar jxvf xcat-dep-*.tar.bz2

 * Verify the following entries are included in the package file specified by the ``otherpkglist`` attribute of the service node osimage. ::

    xcat/xcat-dep/<os>/<arch>/xCATsn
    xcat/xcat-dep/<os>/<arch>/conserver-xcat
    xcat/xcat-dep/<os>/<arch>/perl-Net-Telnet
    xcat/xcat-dep/<os>/<arch>/perl-Expect

   For example, for the osimage *rhels7-x86_64-install-service* ::

    [root@fs4 ~]# lsdef -t osimage rhels7-x86_64-install-service -i otherpkglist
       Object name: rhels7-x86_64-install-service
         otherpkglist=/opt/xcat/share/xcat/install/rh/service.rhels7.x86_64.otherpkgs.pkglist
    [root@fs4 ~]# cat /opt/xcat/share/xcat/install/rh/service.rhels7.x86_64.otherpkgs.pkglist
       xcat/xcat-core/xCATsn
       xcat/xcat-dep/rh7/x86_64/conserver-xcat
       xcat/xcat-dep/rh7/x86_64/perl-Net-Telnet
       xcat/xcat-dep/rh7/x86_64/perl-Expect
    [root@fs4 ~]#

**Note:** you will be installing the xCAT Service Node rpm xCATsn meta-package on the Service Node, not the xCAT Management Node meta-package. Do not install both.

Update the rhels6 RPM repository (rhels6 only)
----------------------------------------------
* This section could be removed after the powerpc-utils-1.2.2-18.el6.ppc64.rpm
  is built in the base rhels6 ISO.
* The direct rpm download link is:
  ``ftp://linuxpatch.ncsa.uiuc.edu/PERCS/powerpc-utils-1.2.2-18.el6.ppc64.rpm``
* The update steps are as following:
  - put the new rpm in the base OS packages ::

        cd /install/rhels6/ppc64/Server/Packages
        mv powerpc-utils-1.2.2-17.el6.ppc64.rpm /tmp
        cp /tmp/powerpc-utils-1.2.2-18.el6.ppc64.rpm .
        # make sure that the rpm is be readable by other users
        chmod +r powerpc-utils-1.2.2-18.el6.ppc64.rpm

* create the repodata ::

      cd /install/rhels6/ppc64/Server
      ls -al repodata/
      total 14316
      dr-xr-xr-x 2 root root    4096 Jul 20 09:34 .
      dr-xr-xr-x 3 root root    4096 Jul 20 09:34 ..
      -r--r--r-- 1 root root 1305862 Sep 22  2010 20dfb74c144014854d3b16313907ebcf30c9ef63346d632369a19a4add8388e7-other.sqlite.bz2
      -r--r--r-- 1 root root 1521372 Sep 22  2010 57b3c81512224bbb5cebbfcb6c7fd1f7eb99cca746c6c6a76fb64c64f47de102-primary.xml.gz
      -r--r--r-- 1 root root 2823613 Sep 22  2010 5f664ea798d1714d67f66910a6c92777ecbbe0bf3068d3026e6e90cc646153e4-primary.sqlite.bz2
      -r--r--r-- 1 root root 1418180 Sep 22  2010 7cec82d8ed95b8b60b3e1254f14ee8e0a479df002f98bb557c6ccad5724ae2c8-other.xml.gz
      -r--r--r-- 1 root root  194113 Sep 22  2010 90cbb67096e81821a2150d2b0a4f3776ab1a0161b54072a0bd33d5cadd1c234a-comps-rhel6-Server.xml.gz
      **-r--r--r-- 1 root root 1054944 Sep 22  2010 98462d05248098ef1724eddb2c0a127954aade64d4bb7d4e693cff32ab1e463c-comps-rhel6-Server.xml**
      -r--r--r-- 1 root root 3341671 Sep 22  2010 bb3456b3482596ec3aa34d517affc42543e2db3f4f2856c0827d88477073aa45-filelists.sqlite.bz2
      -r--r--r-- 1 root root 2965960 Sep 22  2010 eb991fd2bb9af16a24a066d840ce76365d396b364d3cdc81577e4cf6e03a15ae-filelists.xml.gz
      -r--r--r-- 1 root root    3829 Sep 22  2010 repomd.xml
      -r--r--r-- 1 root root    2581 Sep 22  2010 TRANS.TBL
      createrepo \
      -g repodata /98462d05248098ef1724eddb2c0a127954aade64d4bb7d4e693cff32ab1e463c-comps-rhel6-Server.xml

**Note:** you should use ``comps-rhel6-Server.xml`` with its key as the group file.

Install Service Nodes
---------------------

::

  rinstall <service_node> osimage="<osimagename>"

For example ::

  rinstall <service_node> osimage="rhels7-x86_64-install-service"

Monitor the Installation
------------------------

Watch the installation progress using either wcons or rcons: ::

    wcons service     # make sure DISPLAY is set to your X server/VNC or
    rcons <node_name>
    tail -f /var/log/messages

Note: We have experienced one problem while trying to install RHEL6 diskful
Service Node working with SAS disks. The Service Node cannot reboots from SAS
disk after the RHEL6 operating system has been installed. We are waiting for
the build with fixes from RHEL6 team, once meet this problem, you need to
manually select the SAS disk to be the first boot device and boots from the
SAS disk.

Update Service Node Diskful Image
---------------------------------

To update the xCAT software on the Service Node: 

#. Remove previous xcat-core, xcat-dep, and tar files in the NFS mounted ``/install/post/otherpkgs/`` directory: ::
    
    rm /install/post/otherpkgs/<os>/<arch>/xcat/xcat-core
    rm /install/post/otherpkgs/<os>/<arch>/xcat/xcat-dep
    rm /install/post/otherpkgs/<os>/<arch>/xcat/<xcat-core.tar>
    rm /install/post/otherpkgs/<os>/<arch>/xcat/<xcat-dep.tar>

#. Download the desired tar files from xcat.org on to the Management Node, and untar them in the same NFS mounted ``/install/post/otherpkgs/`` directory: ::
 
    cd /install/post/otherpkgs/<os>/<arch>/xcat/
    tar jxvf <new-xcat-core.tar>
    tar jxvf <new-xcat-dep.tar>

#. On the Service Node, run the package manager commands relative to the OS to update xCAT.  For example, on RHEL, use the following yum commands: ::

    yum clean metadata # or yum clean all
    yum update '*xCAT*'


