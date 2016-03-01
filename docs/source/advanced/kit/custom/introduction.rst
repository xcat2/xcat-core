Introduction 
============

Contents
--------

A Software Kit is a tar file that contains the following:

**Kit Configuration File** --- A file describing the contents of this kit and contains following information 

  * Kit name, version, description, supported OS distributions, license information, and deployment parameters
  * Kit repository information including name, supported OS distributions, and supported architectures 
  * Kit component information including name, version, description, server roles, scripts, and other data

**Kit Repositories** --- A directory for each operating system version this kit is supported in. Each directory contains all of the product software packages required for that environment along with repository metadata.

**Kit Components** --- A product "meta package" built to require all of the product software dependencies and to automatically run installation and configuration scripts.

**Kit and Kit Component Files** --- Scripts, deployment parameters, exclusion lists, and other files used to install and configure the kit components and product packages.

**Docs**  [PCM only] [#]_ --- Product documentation shipped as HTML files that can be displayed through the PCM GUI

**Plugins** [PCM only] --- xCAT plugins that can be used for additional product configuration and customization during PCM image management and node management


Kit Components
--------------

Software Kits are deployed to xCAT managed nodes through the xCAT osimage deployment mechanism.  The kit components are inserted into the attributes of the Linux ``osimage`` definition.  The attributes that are modified are the following:

  *  kitcomponents - A list of the kitcomponents assigned to the OS image
  *  serverrole - The role of this OS image that must match one of the supported serverroles of a kitcomponent
  *  otherpkglist - Includes kitcomponent meta package names
  *  postinstall - Includes kitcomponent scripts to run during genimage
  *  postbootscripts - Includes kitcomponent scripts
  *  exlist - Exclude lists for diskless images
  *  otherpkgdir - Kit repositories are linked as subdirectories to this directory

Once the kit components are added to xCAT osimage definitions, administrators can use:

#. standard node deployment for installing the kit components during diskful OS provisioning
#. ``genimage`` command to create a diskless OS image installing the kit components for diskless OS provisioning
#. ``updatenode`` command to install the kit components on existing deployed nodes

The ``kitcomponent`` metadata defines the kit packages as dependency packages and the OS package manager (``yum``, ``zypper``, ``apt-get``) automatically installes the required packages during the xCAT ``otherpkgs`` install process. 

Kit Framework
-------------

With time, the implementation of the xCAT Software Kit support may change.  

In order to process a kit successfully, the kit must be conpatiable with the level of xCAT code that was used to build the kit.  The xCAT kit commands and software kits contain the framework version and compatiable supported versions. 

To view the framework version, use the ``-v | --version`` option on :doc:`addkit </guides/admin-guides/references/man1/addkit.1>`  ::

    # addkit -v
    addkit - xCAT Version 2.11 (git commit 9ea36ca6163392bf9ab684830217f017193815be, built Mon Nov 30 05:43:11 EST 2015)
            kitframework = 2
            compatible_frameworks = 0,1,2


If the commands in the xCAT installation is not compatiable with the Software Kit obtained, update xCAT to a more recent release. 


.. [#] PCM is IBM Platform Cluster Manager 
