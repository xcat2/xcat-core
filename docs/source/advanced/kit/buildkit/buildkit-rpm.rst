Install the xCAT-buildkit RPM
-----------------------------
check to see if xCAT-buildkit RPM is installed in the build server
::
  rpm -qa | grep xCAT-buildkit


The xCAT-buildkit RPM is required to build a kit.  It will be installed automatically as part of installing base xCAT. If the build server is not an xCAT management node, it can be

    #. Download the xCAT tar file and install the xCAT-buildkit RPM from the local repositroy
    #. Install the RPM directly from the internet-hosted repository

Once the repositories are setup, use yum to install xCAT-buildkit and all its dependencies
::
   yum clean metadata
   yum install xCAT-buildkit

For sles, use zypper install and for Ubuntu, use apt-get to install xCAT-buildkit
