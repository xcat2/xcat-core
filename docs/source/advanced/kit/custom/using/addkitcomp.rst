Adding Kit Components
---------------------

Adding Kit Components to an OS Image Definition
```````````````````````````````````````````````

In order to add a kitcomponent to an OS image definition, the kitcomponent must support the OS distro, version, architecture, serverrole for that OS image.

Some kitcomponents have dependencies on other kitcomponents. For example, a kit component may have a dependency on the product kit license component. Any kit components they may be required must also be defined in the xCAT database.

Note: A kit component in the latest product kit may have a dependency on a license kit component from an earlier kit version.

To check if a kitcomponent is valid for an existing OS image definition run the chkkitcomp command: ::

  chkkitcomp -i <osimage> <kitcompname>

If the kit component is compatible then add the kitcomponent to the OS image defintion using the addkitcomp command.  ::

  addkitcomp -a -i <osimage> <kitcompname>

When a kitcomponent is added to an OS image definition, the addkitcomp command will update several attributes in the xCAT database.

Listing kit components
``````````````````````
The xCAT kitcomponent object definition may be listed using the xCAT lsdef command.  ::

  lsdef -t kitcomponent -l <kit component name>

The contents of the kit component may be listed by using the lskitcomponent command.  ::

  lskitcomp <kit component name>


Adding Multiple Versions of the Same Kit Component to an OS Image Definition
`````````````````````````````````````````````````````````````````````````````

xCAT allows to have multiple versions/releases of a product software kit available in the cluster. Typically, different OS image definitions corresponding to the different versions/releases of a product software stack.  However, in some instances, may need mulitple versions/releases of the same product available within a single OS image. This is only feasible if the software product supports the install of multiple versions or releases of its product within an OS image.

Currently, it is not possible to install multiple versions of a product into an OS image using xCAT commands. xCAT uses yum on RedHat and zypper on SLES to install product rpms. These package managers do not provide an interface to install different versions of the same package, and will always force an upgrade of the package. We are investigating different ways to accomplish this function for future xCAT releases.

Some software products have designed their packaging to leave previous versions of the software installed in an OS image even when the product is upgraded. This is done by using different package names for each version/release, so that the package manager does not see the new version as an upgrade, but rather as a new package install. In this case, it is possible to use xCAT to install multiple versions of the product into the same image.

By default, when a newer version/release of a kitcomponent is added to an existing OS image definition, addkitcomp will automatically upgrade the kitcomponent by removing the old version first and then adding the new one. However, user can force both versions of the kitcomponent to be included in the OS image definition by specifying the full kitcomponent name and using the addkitcomp -n (--noupgrade) flag with two separate command calls. For example, to include both myprod_compute.1-0.1 and myprod_compute.1-0.2 into an the compute osimage, you would run in this order: ::

  addkitcomp -i compute myprod_compute.1-0.1
  addkitcomp -i compute -n myprod_compute.1-0.2

  lsdef -t osimage -o compute -i kitcomponents
    Object name:  compute
    kitcomponents=myprod_compute.1-0.1,myprod_compute.1-0.2

When building a diskless image for the first time, or when deploying a diskful node, xCAT will first install version 1-0.1 of myprod, and then in a separate yum or zypper call, xCAT will install version 1-0.2. The second install will either upgrade the product rpms or install the new versions of the rpms depending on how the product named the packages.

Modifying Kit Deployment Parameters for an OS Image Definition
```````````````````````````````````````````````````````````````

Some product software kits include kit deployment parameter files to set environment variables when the product packages are being installed in order to control some aspects of the install process. To determine if a kit includes such a file: ::

  lsdef -t kit -o <kitname> -i kitdeployparams

If the kit does contain a deployment parameter file, the contents of the file will be included in the OS image definition when user add one of the kitcomponents to the image. User can view or change these values if need to change the install processing that they control for the software product: ::

  addkitcomp -i <image> <kitcomponent name>
  vi /install/osimages/<image>/kits/KIT_DEPLOY_PARAMS.otherpkgs.pkglist

NOTE: Be sure to know how changing any kit deployment parameters will impact the install of the product into the OS image. Many parameters include settings for automatic license acceptance and other controls to ensure proper unattended installs into a diskless image or remote installs into a diskful node. Changing these values will cause problems with genimage, updatenode, and other xCAT deployment commands.
