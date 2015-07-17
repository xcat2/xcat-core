Install xCAT
============

xCAT consists of two software packages:

#. **xcat-core**  xCAT's main software package.

     The xcat-core package is provided in one of the following options:

     * **Latest Release (Stable) Builds**

         *This is the latest GA (Generally Availability) build that has been tested throughly*

     * **Latest Snapshot Builds**

         *This is the latest snapshot of the GA version build that may contain bug fixes but has not yet been tested throughly*

     * **Development Builds**

         *This is the snapshot builds of the new version of xCAT in development. This version has not been released yet, use as your own risk*

#. **xcat-dep**  xCAT's dependency package.  This is provided as a convenience for the user and contains dependency packages required by xCAT that are not provided by the operating system.

xCAT is installed by configuring software repositories for ``xcat-core`` and ``xcat-dep`` and using yum package manager.  The software repositoreies can publically hosted (requires internet connectivity) or locally configured.

Configure xCAT Software Repository
----------------------------------

Public Internet Repository
~~~~~~~~~~~~~~~~~~~~~~~~~~

TODO: Need to fill this out

Locally Configured Repository
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

From the xCAT software download page: `<https://sourceforge.net/p/xcat/wiki/Download_xCAT/>`_, download ``xcat-core`` and ``xcat-dep``.

xcat-core
^^^^^^^^^

#. Download xcat-core, if downloading the latest devepment build: ::

        cd /root
        mkdir -p ~/xcat
        cd ~/xcat/
        wget http://sourceforge.net/projects/xcat/files/yum/devel/core-rpms-snap.tar.bz2


#. Extract xcat-core: ::

        cd ~/xcat
        tar jxvf core-rpms-snap.tar.bz

#. Configure the local repository, by runnin the ``mklocalrepo.sh`` script: ::

        cd ~/xcat/xcat-core/
        ./mklocalrepo.sh


xcat-dep
^^^^^^^^

Unless you are downloading ``xcat-dep`` for a specific GA version of xCAT, select the package with the latest timestamp.


#. Download xcat-dep, if downloading xcat-dep from June 11, 2015, for Linux: ::

        mkdir -p ~/xcat/
        cd ~/xcat
        wget http://sourceforge.net/projects/xcat/files/xcat-dep/2.x_Linux/xcat-dep-201506110324.tar.bz2

#. Extract xcat-dep: ::

        cd ~/xcat/
        tar jxvf xcat-dep-201506110324.tar.bz2

#. Configure the local repository by switching to the architecture and os of the system you are installing on , and running the ``mklocalrepo.sh`` script: ::

        cd ~/xcat/xcat-dep/
        # for redhat 6.5 on ppc64...
        cd rh6/ppc64
        ./mklocalrepo.sh

Install xCAT
------------

Install xCAT with the following command: ::

        yum clean all (optional)
        yum install xCAT


**Note:** During the install, you will need to accept the *xCAT Security Key* to proceed: ::

        Retrieving key from file:///root/xcat/xcat-dep/rh6/ppc64/repodata/repomd.xml.key
        Importing GPG key 0xC6565BC9:
         Userid: "xCAT Security Key <xcat@cn.ibm.com>"
         From  : /root/xcat/xcat-dep/rh6/ppc64/repodata/repomd.xml.key
        Is this ok [y/N]:


Verify xCAT Installation
------------------------

Quick verificaiton can be done with the following steps:

#. Source the profile to add xCAT Commands to your path: ::

        source /etc/profile.d/xcat.sh

#. Check the xCAT Install version: ::

        lsxcatd -a

#. Check to see the database is initialized by dumping the site table: ::

        tabdump site

   The output should similar to the following: ::

        #key,value,comments,disable
        "blademaxp","64",,
        "domain","pok.stglabs.ibm.com",,
        "fsptimeout","0",,
        "installdir","/install",,
        "ipmimaxp","64",,
        "ipmiretries","3",,
        ...

Starting and Stopping
---------------------

You can easily start, stop, restart, and check xCAT status using Linux systemd or systemctl:

* start xCAT: ::

    service xcatd start
    systemctl xcatd.service start

* stop xCAT: ::

    service xcatd stop
    systemctl xcatd.service stop

* restart xCAT: ::

    service xcatd restart
    systemctl xcatd.service restart

* check xCAT status: ::

    service xcatd status
    systemctl xcatd.service status


Updating xCAT
-------------

If at a later date you want to update xCAT, simply update the software repository and run: ::

    yum clean metadata (or, yum clean all)
    yum update '*xCAT*'
