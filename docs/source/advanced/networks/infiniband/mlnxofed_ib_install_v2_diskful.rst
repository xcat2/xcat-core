Diskful Installation
====================

#. Prepare dependency packages in the pkglist

   In order for the Mellanox installation script to execute successfully, certain dependency packages are required to be installed on the compute node.  xCAT provides sample package list files to help resolve these dependencies.  The samples are located at ``/opt/xcat/share/xcat/ib/netboot/<os>/``.

   To use the ``/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels7.ppc64le.pkglist``, edit your existing ``pkglist`` file for the target osimage and add the following at the bottom: ::

       #INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels7.ppc64le.pkglist#

#. Configure the ``mlnxofed_ib_install`` script to install the MNLX_OFED drivers

   xCAT has a concept of postscripts that can be used to customize the node after the operating system is installed.  

   Mellanox recommends that the operating system is rebooted after the drivers are installed, so xCAT recommends using the ``postscripts`` attribute to avoid the need for a second reboot.  To invoke the ``mlnxofed_ib_install`` as a postscript ::
 
       chdef -t node -o <node_name> \ 
          -p postscripts="mlnxofed_ib_install -p /install/<path-to>/<MLNX_OFED_LINUX.iso>"

   **[kernel mismatch issue]** The Mellanox OFED ISO is built againt a series of specific kernel version.  If the version of the linux kernel does not match any of the Mellanox offered pre-built kernel modules, you can pass the ``--add-kernel-support`` argument to the Mellanox installation script to build the kernel modules based on the version you are using. ::

       chdef -t node -o <node_name> \ 
          -p postscripts="mlnxofed_ib_install -p /install/<path-to>/<MLNX_OFED_LINUX.iso> \
          -m --add-kernel-support -end-"

#. Provision the node ::

      rinstall <node> osimage=

#. Verification

   * Check the status of ``openibd`` service

     sysVinit: ::

         service openibd status

     systemd: ::
    
         systemctl status openibd.service 

   * Verify that the Mellanox IB drivers are located at: ``/lib/modules/<kernel_version>/extra/``

   * Use the ``ibv_devinfo`` comamnd to obtain information about the InfiniBand adapter.
