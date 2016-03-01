IBM XL Compilers
================

IBM provides XL compilers with advanced optimizing on IBM Power Systems running Linux. 
For more information, http://www-03.ibm.com/software/products/en/xlcpp-linux

Partial Kits
------------

The IBM XL compilers are dependencies for some of the HPC software products and is **not** available in xCAT Software Kit format.  

To assist customers in creating a software kit for the IBM XL compilers, xCAT provides partial kits at: https://xcat.org/files/kits/hpckits/

Creating Compiler Complete Kit
------------------------------

To use software kits that require compiler kit components, a compiler software kit must be available.  The following example will outline the steps required to create the ``xlc-12.1.0.8-151013-ppc64.tar.bz2`` compiler software kit.   Repeat the steps for each compiler kit required.


#. xCAT ``buildkit`` command requires ``createrepo`` is available on the machine: ::

        which createrepo

   If not available, use the default OS package manager to install. (``yum``, ``zypper``, ``apt-get``)

#. Obtain the IBM XL compilers rpms from the IBM Download site.

   **xlc-12.1.0.8** is downloaded to ``/tmp/kits/xlc-12.1.0.8`` ::

        # ls -1 /tmp/kits/xlc-12.1.0.8/
        vac.cmp-12.1.0.8-151013.ppc64.rpm
        vac.lib-12.1.0.8-151013.ppc64.rpm
        vac.lic-12.1.0.0-120323.ppc64.rpm
        vacpp.cmp-12.1.0.8-151013.ppc64.rpm
        vacpp.help.pdf-12.1.0.8-151013.ppc64.rpm
        vacpp.lib-12.1.0.8-151013.ppc64.rpm
        vacpp.man-12.1.0.8-151013.ppc64.rpm
        vacpp.rte-12.1.0.8-151013.ppc64.rpm
        vacpp.rte.lnk-12.1.0.8-151013.ppc64.rpm
        vacpp.samples-12.1.0.8-151013.ppc64.rpm
        xlc_compiler-12.1.0.8-151013.noarch.rpm
        xlc_compute-12.1.0.8-151013.noarch.rpm
        xlc_license-12.1.0.8-151013.noarch.rpm
        xlc_rte-12.1.0.8-151013.noarch.rpm
        xlmass.lib-7.1.0.8-151013.ppc64.rpm
        xlsmp.lib-3.1.0.8-151013.ppc64.rpm
        xlsmp.msg.rte-3.1.0.8-151013.ppc64.rpm
        xlsmp.rte-3.1.0.8-151013.ppc64.rpm
  
#. Obtain the corresponding compiler partial kit from https://xcat.org/files/kits/hpckits/. [#]_

   **xlc-12.1.0.8-151013-ppc64.NEED_PRODUCT_PKGS.tar.bz2** is downloaded to ``/tmp/kits``: ::

        xlc-12.1.0.8-151013-ppc64.NEED_PRODUCT_PKGS.tar.bz2


#. Complete the partial kit by running the ``buildkit addpkgs`` command: ::

       buildkit addpkgs xlc-12.1.0.8-151013-ppc64.NEED_PRODUCT_PKGS.tar.bz2 \ 
          --pkgdir /tmp/kits/xlc-12.1.0.8

   Sample output: ::
 
       Extracting tar file /tmp/kits/xlc-12.1.0.8-151013-ppc64.NEED_PRODUCT_PKGS.tar.bz2. Please wait.
       Spawning worker 0 with 5 pkgs
       Spawning worker 1 with 5 pkgs
       Spawning worker 2 with 4 pkgs
       Spawning worker 3 with 4 pkgs
       Workers Finished
       Saving Primary metadata
       Saving file lists metadata
       Saving other metadata
       Generating sqlite DBs
       Sqlite DBs complete
       Creating tar file /tmp/kits/xlc-12.1.0.8-151013-ppc64.tar.bz2.
       Kit tar file /tmp/kits/xlc-12.1.0.8-151013-ppc64.tar.bz2 successfully built. 



#. The complete kit, ``/tmp/kits/xlc-12.1.0.8-151013-ppc64.tar.bz2`` is ready to be used.


.. [#] If the partial kit for the version needed does not exist on the download site, open an `issue <https://github.com/xcat2/xcat-core/issues>`_ to the xcat development team.
