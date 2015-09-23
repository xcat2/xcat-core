Installing the xCAT-buildkit
-----------------------------

The xCAT-buildkit RPM is required to build a kit.  It will be installed automatically as part of installing base xCAT. If the build server is not an xCAT management node, it can be

    #. Download the xCAT tar file and install the xCAT-buildkit RPM from the local repositroy
    #. Install the RPM directly from the internet-hosted repository

Once the repositories are setup, install xCAT-buildkit and all its dependencies.

**[RHEL]** ::

   yum clean metadata
   yum install xCAT-buildkit

**[SLES]** ::

  zypper clean
  zypper install xCAT-buildkit


**[UBUNTU]** ::

  apt-get clean
  apt-get install xCAT-buildkit

