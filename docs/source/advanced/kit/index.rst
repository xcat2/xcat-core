Software Kits
=============

xCAT supports a unique software bundling concept called **software kits**.  Software kit combines all of the required product components (packages, license, configuration, scripts, etc) to assist the administrator in the installation of software onto machines managed by xCAT.  Software kits are made up of a collection of "kit components", each of which is tailored to one specific environment for that particular version of the software product. 

Prebuilt software kits are available as a tar file which can be downloaded and then added to the xCAT installation.  After the kits are added to xCAT, kit components are then added to specific xCAT osimages to automatically install the software bundled with the kit during OS deployment.  In some instances, software kits may be provided as partial kits.  Partial kits need additional effort to complete the kit before it can be used by xCAT. 

Software kits are supported for both diskful and diskless image provisioning.

.. toctree::
   :maxdepth: 2

   hpc/index.rst
   custom/index.rst
