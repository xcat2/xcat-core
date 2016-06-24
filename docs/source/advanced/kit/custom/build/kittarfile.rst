Build Tar File
==============

After the Kit package repositories are built, run the ``buildtar`` subcommand in the Kit directory to build the final kit tarfile.  ::

  buildkit buildtar

The tar file will be built in the kit directory location.  A complete kit will be named: ::

  ex: kitname-1.0.0-x86_64.tar.bz2

A partial kit will have "NEED_PRODUCT_PKGS" string in its name: ::

  ex: kitname-1.0.0-x86_64.NEED_PRODUCT_PKGS.tar.bz2


Using Partial Kits with newer Software Versions
------------------------------------------------

If the product packages are for a newer version or release than what specified in the partial kit tar file name, user may still be able to build a complete kit with the packages, assuming that the partial kit is compatible with those packages.

Note: Basically, the latest partial kit available online will work until there is a newer version available.

To build a complete kit with the new software, user can provide the new version and/or release of the software on the buildkit command line.  ::

  buildkit addpkgs <kitname.NEED_PRODUCT_PKGS.tar.bz2> --pkgdir <product package directories> \
       --kitversion <new version> --kitrelease <new release>

For example, if the partial kit was created for a product version of 1.3.0.2 but wish to complete a new kit for product version 1.3.0.4 then can add "-k 1.3.0.4" to the buildkit command line.


Completing a partial kit
------------------------

Follow these steps to complete the kit build process for a partial kit.

  #. copy the partial kit to a working directory
  #. copy the product software packages to a convenient location or locations
  #. cd to the working directory
  #. Build the complete kit tarfile 

::

    buildkit addpkgs <kit.NEED_PRODUCT_PKGS.tar.bz2> --pkgdir <product package directories>

The complete kit tar file will be created in the working directory



