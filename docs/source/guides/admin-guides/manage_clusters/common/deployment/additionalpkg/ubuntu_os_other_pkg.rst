Install Additional Other Packages with Ubuntu official mirror
==============================================================

The Ubuntu ISO used to install the compute nodes only include packages to run a minimal base operating system, it is likely that users will want to install additional Ubuntu packages from the internet Ubuntu repositories or local repositories, this section describes how to install additional Ubuntu packages.

Compute nodes can access the internet
-------------------------------------

#. Specify the repository

   Define the **otherpkgdir** attribute in osimage to use the internet repository directly.: ::

    chdef -t osimage <osimage name> otherpkgdir="http://us.archive.ubuntu.com/ubuntu/ \
    $(lsb_release -sc) main,http://us.archive.ubuntu.com/ubuntu/ $(lsb_release -sc)-update main"

#. Define the otherpkglist file

   create an **otherpkglist** file: ``/install/custom/install/ubuntu/compute.otherpkgs.pkglist``, add the package names into this file, and modify the ``otherpkglist`` attribute in the osimage. ::

    chdef -t osimage <osimage name> otherpkglist=/install/custom/install/ubuntu/compute.otherpkgs.pkglist

#. Run ``updatenode <noderange> -S`` or ``updatenode <noderange> -P otherpkgs``

   Run ``updatenode -S`` to **install/update** the packages on the compute nodes ::

    updatenode <noderange> -S

   Run ``updatenode -P otherpkgs`` to **install/update** the packages on the compute nodes ::

    updatenode <noderange> -P otherpkgs

Compute nodes can not access the internet
------------------------------------------

If compute nodes cannot access the internet, there are two ways to install additional packages

   * Use local mirror
      Please refer the Ubuntu document below for how to set up your own local Ubuntu mirror.
      https://help.ubuntu.com/community/Rsyncmirror
   * Use apt-proxy
      Please refer the Ubuntu document below for how to setup a apt-proxy server.
      https://help.ubuntu.com/community/AptProxy
   * Setting up apt-get to use a http-proxy.
      Please refer the Ubuntu document below for how to do set up it.
      https://help.ubuntu.com/community/AptGet/Howto#Setting_up_apt-get_to_use_a_http-proxy
