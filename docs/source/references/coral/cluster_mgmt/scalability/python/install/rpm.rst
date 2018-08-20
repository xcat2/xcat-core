Using RPM (recommended)
=======================

**Support is only for RHEL 7.5 for Power LE (Power 9)**

The following repositories should be configured on your Management Node (and Service Nodes).

   * RHEL 7.5 OS Repository
   * RHEL 7.5 Extras Repository
   * RHEL 7 EPEL Repo (https://fedoraproject.org/wiki/EPEL)
   * Fedora28 Repo (for ``gevent``, ``greenlet``)

#. Configure the MN/SN to the RHEL 7.5 OS Repo

#. Configure the MN/SN to the RHEL 7.5 Extras Repo

#. Configure the MN/SN to the EPEL Repo  (https://fedoraproject.org/wiki/EPEL)

#. Create a local Fedora28 Repo and Configure the MN/SN to the FC28 Repo

   Here's  an example to configure the Fedora 28 repo at ``/install/repos/fc28``

   #. Make the target repo directory on the MN: ::

        mkdir -p /install/repos/fc28/ppc64le/Packages

   #. Download the rpms from the Internet: ::

        cd /install/repos/fc28/ppc64le/Packages
        wget https://www.rpmfind.net/linux/fedora-secondary/development/rawhide/Everything/ppc64le/os/Packages/p/python2-gevent-1.2.2-2.fc28.ppc64le.rpm
        wget https://www.rpmfind.net/linux/fedora-secondary/development/rawhide/Everything/ppc64le/os/Packages/p/python2-greenlet-0.4.13-2.fc28.ppc64le.rpm

    #. Create a yum repo in that directory: ::

        cd /install/repos/fc28/ppc64le/
        createrepo .

#. Install ``xCAT-openbmc-py`` using ``yum``: ::

      yum install xCAT-openbmc-py

   **Note**: The install will fail if the dependencies cannot be met.
