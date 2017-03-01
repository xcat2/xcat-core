Diskless Installation
=====================

#. Prepare dependency packages in the pkglist 

   In order for the Mellanox installation script to execute successfully, certain dependency packages are required to be installed on the compute node.  xCAT provides sample package list files to help resolve these dependencies.  The samples are located at ``/opt/xcat/share/xcat/ib/netboot/<os>/``.

   To use the ``/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels7.ppc64le.pkglist``, edit your existing ``pkglist`` file for the target osimage and add the following at the bottom: ::

       #INCLUDE:/opt/xcat/share/xcat/ib/netboot/rh/ib.rhels7.ppc64le.pkglist#

#. Configure the ``mlnxofed_ib_install`` script to install the MNLX_OFED drivers

   Edit the ``postinstall`` script on the osimage to invoke the ``mlnxofed_ib_install`` install script.  

       For example, take ``rhels7.2-ppc64le-netboot-compute``: 

           #. Find the path to the ``postinstall`` script: :: 
    
                  # lsdef -t osimage -o rhels7.2-ppc64le-netboot-compute -i postinstall
                  Object name: rhels7.2-ppc64le-netboot-compute
                      postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall

           #. Edit the ``/opt/xcat/share/xcat/netboot/rh/compute.rhels7.ppc64le.postinstall`` and add the following: ::
    
                  /install/postscripts/mlnxofed_ib_install \
                     -p /install/<path-to>/<MLNX_OFED_LINUX.iso> -i $1 -n genimage
    
              *Note: The $1 is a argument that is passed to the the postinstall script at runtime.*

   **[kernel mismatch issue]** The Mellanox OFED ISO is built againt a series of specific kernel version.  If the version of the linux kernel does not match any of the Mellanox offered pre-built kernel modules, you can pass the ``--add-kernel-support`` argument to the Mellanox installation script to build the kernel modules based on the version you are using. ::

       /install/postscripts/mlnxofed_ib_install \
         -p /install/<path-to>/<MLNX_OFED_LINUX.iso> -m --add-kernel-support -end- \
         -i $1 -n genimage
    
#. Generate the diskless image 

   Use the ``genimage`` command to generate the diskless image from the osimage definition ::
        
	genimage <osimage>

   Use the ``packimage`` command to pack the diskless image for deployment ::

	packimage <osimage>

#. Provision the node ::

     rinstall <node> osimage=rhels7.2-ppc64le-netboot-compute
   
#. Verification

   * Check the status of ``openibd`` service

     sysVinit: ::

         service openibd status

     systemd: ::
    
         systemctl status openibd.service 

   * Verify that the Mellanox IB drivers are located at: ``/lib/modules/<kernel_version>/extra/``

   * Use the ``ibv_devinfo`` comamnd to obtain information about the InfiniBand adapter.
