
.. BEGIN_see_release_notes

For the current list of operating systems supported and verified by the development team for the different releases of xCAT, see the :doc:`xCAT2 Release Notes </overview/xcat2_release>`.

**Disclaimer** These instructions are intended to only be guidelines and specific details may differ slightly based on the operating system version.  Always refer to the operating system documentation for the latest recommended procedures.


.. END_see_release_notes

.. BEGIN_install_os_mgmt_node

Install one of the supported operating systems on your target management node.

The system requirements for your xCAT management node largely depend on the size of the cluster you plan to manage and the type of provisioning used (diskful, diskless, system clones, etc).  The majority of system load comes during cluster provisioning time.

**Memory Requirements:**

+--------------+-------------+
| Cluster Size | Memory (GB) |
+==============+=============+
| Small (< 16) | 4-6         |
+--------------+-------------+
| Medium       | 6-8         |
+--------------+-------------+
| Large        | > 16        |
+--------------+-------------+


.. END_install_os_mgmt_node

.. BEGIN_install_xcat_introduction

xCAT consists of two software packages: ``xcat-core`` and ``xcat-dep``

#. **xcat-core**  xCAT's main software package and is provided in one of the following options:

     * **Latest Release (Stable) Builds**

         *This is the latest GA (Generally Availability) build that has been tested thoroughly*

     * **Development Builds**

         *This is the snapshot builds of the new version of xCAT in development. This version has not been released yet, use as your own risk*

#. **xcat-dep**  xCAT's dependency package.  This package is provided as a convenience for the user and contains dependency packages required by xCAT that are not provided by the operating system.


.. END_install_xcat_introduction

.. BEGIN_installation_methods

The following sections describe the different methods for installing xCAT.

.. END_installation_methods

.. BEGIN_automatic_install

``go-xcat`` is a tool that can be used to fully install or update xCAT.  ``go-xcat`` will automatically download the correct package manager repository file from xcat.org and use the public repository to install xCAT.  If the xCAT management node does not have internet connectivity, use process described in the Manual Installation section of the guide.

#. Download the ``go-xcat`` tool using ``wget``: ::

        wget https://raw.githubusercontent.com/xcat2/xcat-core/master/xCAT-server/share/xcat/tools/go-xcat -O - >/tmp/go-xcat
        chmod +x /tmp/go-xcat

#. Run the ``go-xcat`` tool: ::

        /tmp/go-xcat install            # installs the latest stable version of xCAT
        /tmp/go-xcat -x devel install   # installs the latest development version of xCAT

.. END_automatic_install

.. BEGIN_configure_xcat_local_repo_xcat-core_RPM

**[xcat-core]**

#. Download xcat-core: ::

        # downloading the latest development build, core-rpms-snap.tar.bz2
        mkdir -p ~/xcat
        cd ~/xcat/
        wget http://xcat.org/files/xcat/xcat-core/devel/Linux/core-snap/core-rpms-snap.tar.bz2


#. Extract xcat-core: ::

        tar jxvf core-rpms-snap.tar.bz2

#. Configure the local repository for xcat-core by running ``mklocalrepo.sh`` script in the ``xcat-core`` directory: ::

        cd ~/xcat/xcat-core
        ./mklocalrepo.sh


.. END_configure_xcat_local_repo_xcat-core_RPM

.. BEGIN_configure_xcat_local_repo_xcat-core_DEBIAN

**[xcat-core]**

#. Download xcat-core: ::

        # downloading the latest development build, core-rpms-snap.tar.bz2
        mkdir -p ~/xcat
        cd ~/xcat/
        wget http://xcat.org/files/xcat/xcat-core/devel/Ubuntu/core-snap/core-debs-snap.tar.bz2


#. Extract xcat-core: ::

        tar jxvf core-debs-snap.tar.bz2

#. Configure the local repository for xcat-core by running ``mklocalrepo.sh`` script in the ``xcat-core`` directory: ::

        cd ~/xcat/xcat-core
        ./mklocalrepo.sh


.. END_configure_xcat_local_repo_xcat-core_DEBIAN

.. BEGIN_configure_xcat_local_repo_xcat-dep_RPM

**[xcat-dep]**

Unless you are downloading ``xcat-dep`` to match a specific package tested with a GA release, it's recommended to download the latest version of xcat-dep.


#. Download xcat-dep: ::

        # if downloading xcat-dep from June 11, 2015, xcat-dep-201506110324.tar.bz2
        mkdir -p ~/xcat/
        cd ~/xcat
        wget http://xcat.org/files/xcat/xcat-dep/2.x_Linux/xcat-dep-201506110324.tar.bz2

#. Extract xcat-dep: ::

        tar jxvf xcat-dep-201506110324.tar.bz2

#. Configure the local repository for xcat-dep by switching to the architecture and os subdirectory of the node you are installing on, then run the ``mklocalrepo.sh`` script: ::

        cd ~/xcat/xcat-dep/
        # Example, on redhat 7.1 ppc64le: cd rh7/ppc64le
        cd <os>/<arch>
        ./mklocalrepo.sh

.. END_configure_xcat_local_repo_xcat-dep_RPM

.. BEGIN_configure_xcat_local_repo_xcat-dep_DEBIAN

**[xcat-dep]**

Unless you are downloading ``xcat-dep`` to match a specific package tested with a GA release, it's recommended to download the latest version of xcat-dep.


#. Download xcat-dep: ::

        # if downloading xcat-dep from June 11, 2015, xcat-dep-ubuntu-snap20150611.tar.bz
        mkdir -p ~/xcat/
        cd ~/xcat
        wget http://xcat.org/files/xcat/xcat-dep/2.x_Ubuntu/xcat-dep-ubuntu-snap20150611.tar.bz

#. Extract xcat-dep: ::

        tar jxvf xcat-dep-ubuntu-snap20150611.tar.bz

#. Configure the local repository for xcat-dep by running the ``mklocalrepo.sh`` script: ::

        cd ~/xcat/xcat-dep/
        ./mklocalrepo.sh

.. END_configure_xcat_local_repo_xcat-dep_DEBIAN


.. BEGIN_verifying_xcat

Quick verification of the xCAT Install can be done running the following steps:

#. Source the profile to add xCAT Commands to your path: ::

        source /etc/profile.d/xcat.sh

#. Check the xCAT version: ::

        lsxcatd -a

#. Check to verify that the xCAT database is initialized by dumping out the site table: ::

        tabdump site

   The output should be similar to the following: ::

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

xCAT is started automatically after the installation, but the following commands can be used to start, stop, restart, and check xCAT status.

* start xCAT: ::

    service xcatd start
    [systemd] systemctl start xcatd.service

* stop xCAT: ::

    service xcatd stop
    [systemd] systemctl stop xcatd.service

* restart xCAT: ::

    service xcatd restart
    [systemd] systemctl restart xcatd.service

* check xCAT status: ::

    service xcatd status
    [systemd] systemctl status xcatd.service


.. END_verifying_xcat

