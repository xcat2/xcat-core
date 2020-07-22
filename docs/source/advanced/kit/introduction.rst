
Introduction 
============

Overview
--------

xCAT supports a unique software bundling concept called kits. A software kit combines all of the required product packages with configuration information, scripts, and other files to easily install a software product onto an xCAT node or in an xCAT OS image based on the role that node performs in the cluster. A software kit is made up of a collection of kit components, each of which is tailored to one specific environment for that particular version of the product.

A software kit is available as a tar file that is downloaded and added to your xCAT management node. The kit components resident in that kit can then be added to an existing xCAT OS image definition and then either be installed on a stateful node during node deployment, added to an active stateful node with the updatenode command, or built into a diskless OS image with the genimage command.

Typically, a software kit will contain all of the product package files. However, in some instances, software kits may be delivered as partial or incomplete kits, and not be bundled with all of the product packages. You will then need to obtain your product packages through your reqular distribution channels, download them to a server along with the partial kit, and run the buildkit addpkgs command to build a complete kit that can be used by xCAT.


Contents of a software Kit
--------------------------
A software kit is a tar file that contains the following

**Kit Configuration File** --- A file describing the contents of this kit and contains following information 

  * Kit name, version, description, supported OS distributions, license information, and deployment parameters
  * Kit repository information including name, supported OS distributions, and supported architectures 
  * Kit component information including name, version, description, server roles, scripts, and other data

**Kit Repositories** --- A directory for each operating system version this kit is supported in. Each directory contains all of the product software packages required for that environment along with repository metadata.

**Kit Components** --- A product "meta package" built to require all of the product software dependencies and to automatically run installation and configuration scripts.

**Kit and Kit Component Files** --- Scripts, deployment parameters, exclusion lists, and other files used to install and configure the kit components and product packages.

**Docs**   (for use with PCM only) --- Product documentation shipped as HTML files that can be displayed through the PCM GUI

**Plugins**   (for use with PCM only) --- xCAT plugins that can be used for additional product configuration and customization during PCM image management and node management

Kit Component in a osimage
--------------------------
Software Kits are deployed to xCAT nodes through the standard xCAT OS image deployment mechanisms. Various pieces of a kit component are inserted into the attributes of a Linux OS image definition. Some of the attributes that are modified are:

  * kitcomponents - A list of the kitcomponents assigned to the OS image
  *  serverrole - The role of this OS image that must match one of the supported serverroles of a kitcomponent
  *  otherpkglist - Includes kitcomponent meta package names
  *  postinstall - Includes kitcomponent scripts to run during genimage
  *  postbootscripts - Includes kitcomponent scripts
  *  exlist - Exclude lists for diskless images
  *  otherpkgdir - Kit repositories are linked as subdirectories to this directory

When a kitcomponent is added to an OS image definition, these attributes are automatically updated.

User can then use the genimage command to install the kitcomponents into the diskless OS image, the standard node deployment process for stateful nodes, or the xCAT updatenode command to update the OS on an active compute node. Since the kitcomponent meta package defines the product packages as dependencies, the OS package manager (yum, zypper, apt-get) automatically installs all the required product packages during the xCAT otherpkgs install process.

Kit Frameworks
--------------
Over time it is possible that the details of the Kit package contents and support may change. For example, there may be a need for additional information to be added etc. We refer to a particular instance of the kit support as its "framework". A particular framework is identified by a numerical value.

In order to process a kit properly it must be compatible with the level of code that was used to build the kit.

Both the kit commands and the actual kits contain the current framework they support as well as any backlevel versions also supported.

View the supported framework and compatible framework values for a command can be used the ``-v|--version`` option.  ::

   addkit -v
   addkit - xCAT Version 2.8.3 (built Sat Aug 31 11:11:31 EDT 2013)
           kitframework = 2
           compatible_frameworks = 0,1,2

When a Kit is being used to update an osimage, the Kit commands will check to see if the Kit framework value is compatible. To be compatible at least one of the Kit compatible_frameworks must match one of the compatible frameworks the command supports.

If the commands you are using are not compatible with the Kit you have, have to update xCAT to get the appropriate framework. Typically this will amount to updating xCAT to the most recent release.
