Creating a New Kit
==================

Use the :doc:`buildkit </guides/admin-guides/references/man1/buildkit.1>` command to create a kit template directory structure ::

    buildkit create <kitbasename> [-l|--kitloc <kit location>]


Kit Directory 
-------------

The Kit directory location will be automatically  populated with additional subdirecotries and samples: 

**buildkit.conf** -  The sample Kit build configuration file.

**source_packages** - This directory stores the source packages for Kit Packages and Non-Native Packages.  The **buildkit** command will search these directories for source packages when building packages.  This directory stores:
  
  * RPM spec and tarballs. (A sample spec file is provided.)
  * Source RPMs.
  * Pre-built RPMs (contained in a subdirectory of source_packages)
  * Non-Native Packages

**scripts** - This directory stores the Kit Deployment Scripts.  Samples are provided for each type of script.

**plugins** - This directory stores the Kit Plugins. Samples are provided for each type of plugin.

**docs** - This directory stores the Kit documentation files.

**other_files**

  * **kitdeployparams.lst**: Kit Deployment parameters file
  * **exclude.lst**: File containing files/dirs to exclude in stateless image.

**build** - This directory stores files when the Kit is built.

  * **kit_repodir** - This directory stores the fully built Kit Package Repositories
  * **<kitbasename>** -  This directory stores the contents of the Kit tarfile before it is tar'red up.

**<kitname>** - The kit tar file, partial kit name or complete kit tar file name (ex. kitname.tar.bz2)


Kit Configuration File
----------------------

The ``buildkit.conf`` file is a sample file that contains a description of all the supported attributes and indicates required or optional fields.  The user needs to modify this file for the software kit to be built. [#]_ 

**kit** --- This stanza defines general information for the Kit.  There must be exactly one kit stanza in a kit build file.  ::

    kit:
      basename=pperte
      description=Parallel Environment Runtime Edition
      version=1.3.0.6
      release=0
      ostype=Linux
      osarch=x86_64
      kitlicense=ILAN           <== the default kit license string is "EPL"
      kitdeployparams=pe.env    <== pe.env has to define in the other_files dir.

**kitrepo** --- This stanza defines a Kit Package Repository. There must be at least one kitrepo stanza in a kit build file.  If this kit need to support multiple OSes, user should create a separate repository for each OS.  Also, no two repositories can be defined with the same OS name, major version, and arch.  ::

  kitrepo:
      kitrepoid=rhels6_x86_64
      osbasename=rhels
      osmajorversion=6
      osarch=x86_64

    kitrepo:
      kitrepoid=sles11_x86_64
      osbasename=sles
      osmajorversion=11
      osarch=x86_64

minor version can be support following format: ::
    
    osminorversion=2  <<-- minor version has to be exactly matched to 2
    osminorversion=>=2  <<-- minor version can be 2 or greater than 2
    osminorversion=<=2  <<-- minor version can be 2 or less than 2 
    osminorversion=>2  <<-- minor version has to be greater than 2
    osminorversion=<2  <<-- minor version has to be less than 2 

**kitcomponent** --- This stanza defines one Kit Component. A kitcomponent definition is a way of specifying a subset of the product Kit that may be installed into an xCAT osimage.  A kitcomponent may or may not be dependent on other kitcomponents.If user want to build a component which supports multiple OSes, need to create one kitcomponent stanza for each OS.  ::

  kitcomponent:
       basename=pperte_license
       description=PE RTE for compute nodes
       serverroles=compute
       # These packages must be shipped with the OS distro
       ospkgdeps=at,rsh,rsh-server,xinetd,sudo,libibverbs(x86-32),libibverbs(x86-64),redhat-lsb
       kitrepoid=rhels6_x86_64
       kitpkgdeps=ppe_rte_license
  kitcomponent:
       basename=pperte_compute
       description=PE RTE for compute nodes
       serverroles=compute
       kitrepoid=rhels6_x86_64
       kitcompdeps=pperte_license
       kitpkgdeps=pperte,pperteman,ppertesamples,src
       exlist=pe.exlist   <=== the file needs to define in the other_files dir
       # All those post script need to define in the scripts dir
       postinstall=pperte_postinstall
       postupgrade=pperte_postinstall
       postbootscripts=pperte_postboot
  kitcomponent:
       basename=pperte_license
       description=PE RTE for compute nodes
       serverroles=compute
       ospkgdeps=at,rsh-server,xinetd,sudo,libibverbs-32bit,libibverbs,insserv
       kitrepoid=sles11_x86_64
       kitpkgdeps=ppe_rte_license  


**kitpackage** --- This stanza defines Kit Package (ie. RPM). There can be zero or more kitpackage stanzas.  For multiple package supports,  need to 

  #. Define one kitpackage section per supported OS.  or
  #. Define one kitpacakge stanza which contains multiple kitrepoid lines. For the RPM packages, users need to responsible for createing an RPM spec file that can run on multiple OSes.  

::

  kitpackage:
      filename=pperte-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=pperteman-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=ppertesamples-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=ppe_rte_*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=ppe_rte_man-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=ppe_rte_samples-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  kitpackage:
      filename=src-*.i386.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64
  #License rpm gets placed in all repos
  kitpackage:
      filename=ppe_rte_license-*.x86_64.rpm
      kitrepoid=rhels6_x86_64,sles11_x86_64


.. [#] The latest version of the ``buildkit.conf`` file is located in the ``/opt/xcat/share/xcat/kits/kit_template`` directory.


Partial vs. Complete Kits
-------------------------

A **complete** software kits includes all the product software and is ready to be consumed as is.   A **partial** software kit is one that does not include all the product packages and requires the consumer to download the product software and complete the kit before it can be consumed.  

To build partial kits, the ``isexternalpkg=yes`` needs to be set in the ``kitpackage`` stanza in the ``buildkit.conf`` file: ::

  kitpackage:
    filename=foobar_runtime-*.x86_64.rpm
    kitrepoid=rhels6_x86_64
    isexternalpkg=yes
