Diskful (Stateful) Installation
===============================

Any cluster using statelite compute nodes must use a stateful (diskful) Service Nodes.

**Note: All xCAT Service Nodes must be at the exact same xCAT version as the xCAT Management Node**. Copy the files to the Management Node (MN) and untar them in the appropriate sub-directory of ``/install/post/otherpkgs``

**Note for the appropriate directory below, check the ``otherpkgdir=/install/post/otherpkgs/rhels7/x86_64`` attribute of the osimage defined for the servicenode.**
 
For example, for osimage rhels7-x86_64-install-service ::

    mkdir -p /install/post/otherpkgs/**rhels7**/x86_64/xcat
    cd /install/post/otherpkgs/**rhels7**/x86_64/xcat
    tar jxvf core-rpms-snap.tar.bz2
    tar jxvf xcat-dep-*.tar.bz2

Next, add rpm names into your own version of service.<osver>.<arch>.otherpkgs.pkglist file. In most cases, you can find an initial copy of this file under ``/opt/xcat/share/xcat/install/<platform>`` . Or copy one from another similar platform. :: 

    mkdir -p /install/custom/install/rh
    cp /opt/xcat/share/xcat/install/rh/service.rhels7.x86_64.otherpkgs.pkglist \
       /install/custom/install/rh
    vi /install/custom/install/rh/service.rhels7.x86_64.otherpkgs.pkglist

Make sure the following entries are included in the
/install/custom/install/rh/service.rhels7.x86_64.otherpkgs.pkglist: ::

    xCATsn
    conserver-xcat
    perl-Net-Telnet
    perl-Expect

**Note: you will be installing the xCAT Service Node rpm xCATsn meta-package on the Service Node, not the xCAT Management Node meta-package. Do not install both.**

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

**Note:** you should use comps-rhel6-Server.xml with its key as the group file.

Set the node status to ready for installation
---------------------------------------------

Run nodeset to the osimage name defined in the provmethod attribute on your Service Node. ::

  nodeset service osimage="<osimagename>"

For example ::

  nodeset <service_node> osimage="rhels7-x86_64-install-service"

Initialize network boot to install Service Nodes
------------------------------------------------

::

  rsetboot <service_node> net
  rpower <service_node> boot

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

Update Service Node Diskfull Image
----------------------------------

To update the xCAT software on the Service Node: 

#. Obtain the new xcat-core and xcat-dep RPMS 
#.
