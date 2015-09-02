.. _Install-Additional-OS-Packages-label:

Install Additional OS Packages
==============================

Installing Additional Packages using OS Distro Packages
---------------------------------------------------------

For rpms from the OS distro, add the new rpm names (without the version number) in the .pkglist file. For example, file /install/custom/netboot/sles/compute.pkglist will look like this after adding perl-DBI: ::

        bash
        nfs-utils
        openssl
        dhcpcd
        kernel-smp
        openssh
        procps
        psmisc
        resmgr
        wget
        rsync
        timezone
        perl-DBI

For the format of the .pkglist file, 
see :ref:`File-Format-for-pkglist-label`

If you have newer updates to some of your operating system packages that you would like to apply to your OS image, you can place them in another directory, and add that directory to your osimage pkgdir attribute. For example, with the osimage defined above, if you have a new openssl package that you need to update for security fixes, you could place it in a directory, create repository data, and add that directory to your pkgdir: ::

       mkdir -p /install/osupdates/rhels6.3/x86_64 
       cd /install/osupdates/rhels6.3/x86_64
       cp <your new openssl rpm>  .
       createrepo .
       chdef -t osimage rhels6.3-x86_64-netboot-compute pkgdir=/install/rhels6/x86_64,/install/osupdates/rhels6.3/x86_64

Note:If the objective node is not installed by xCAT,please make sure the correct osimage pkgdir attribute so that you could get the correct repository data. 

.. _File-Format-for-pkglist-label:

File Format for .pkglist File
-----------------------------------------

The .pklist file is used to specify the rpm and the group/pattern names from os distro that will be installed on the nodes. It can contain the following types of entries: ::

  * rpm name without version numbers
  * group/pattern name marked with a '@' (for full install only)
  * rpms to removed after the installation marked with a "-" (for full install only)

These are described in more details in the following sections.

RPM Names
~~~~~~~~~

A simple .pkglist file just contains the the name of the rpm file without the version numbers.

For example, ::

    openssl
    xntp
    rsync
    glibc-devel.i686

Include pkglist Files
~~~~~~~~~~~~~~~~~~~~~

The #INCLUDE statement is supported in the pkglist file.

You can group some rpms in a file and include that file in the pkglist file using #INCLUDE:<file># format. ::

    openssl
    xntp
    rsync
    glibc-devel.1686
    #INCLUDE:/install/post/custom/rh/myotherlist#

where /install/post/custom/rh/myotherlist is another package list file that follows the same format.

Note: the trailing "#" character at the end of the line. It is important to specify this character for correct pkglist parsing.

Group/Pattern Names
~~~~~~~~~~~~~~~~~~~

It is only supported for statefull deployment.

In Linux, a groups of rpms can be packaged together into one package. It is called a group on RedHat, CentOS, Fedora and Scientific Linux. To get the a list of available groups, run ::

    yum grouplist

On SLES, it is called a pattern. To list all the available patterns, run ::

    zypper se -t pattern

You can specify in this file the group/pattern names by adding a '@' and a space before the group/pattern names. For example: ::

    @ base

Remove RPMs After Installing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

It is only supported for statefull deployment.

You can specify in this file that certain rpms to be removed after installing the new software. This is done by adding '-' before the rpm names you want to remove. For example: ::

    wget


.. _Install-Additional-Other-Packages-label:

Install Additional Other Packages
=================================

Installing Additional Packages Using an Otherpkgs Pkglist
----------------------------------------------------------

If you have additional rpms (rpms ** not ** in the distro) that you also want installed, make a directory to hold them, create a list of the rpms you want installed, and add that information to the osimage definition: ::

    Create a directory to hold the additional rpms:

    mkdir -p /install/post/otherpkgs/rh/x86_64
    cd /install/post/otherpkgs/rh/x86_64
    cp /myrpms/* .
    createrepo .

** NOTE **: when the management node is rhels6.x, and the otherpkgs repository data is for rhels5.x, we should run createrepo with "-s md5". Such as: ::

createrepo -s md5 .

    * Create a file that lists the additional rpms that should be installed. For example, in /install/custom/netboot/rh/compute.otherpkgs.pkglist put: ::

    myrpm1
    myrpm2
    myrpm3

    * Add both the directory and the file to the osimage definition: ::

    chdef -t osimage mycomputeimage otherpkgdir=/install/post/otherpkgs/rh/x86_64 otherpkglist=/install/custom/netboot/rh/compute.otherpkgs.pkglist

If you add more rpms at a later time, you must run createrepo again. The createrepo command is in the createrepo rpm, which for RHEL is in the 1st DVD, but for SLES is in the SDK DVD.

If you have ** multiple sets of rpms ** that you want to ** keep separate ** to keep them organized, you can put them in separate sub-directories in the otherpkgdir. If you do this, you need to do the following extra things, in addition to the steps above:

    * Run createrepo in each sub-directory

    * In your otherpkgs.pkglist, list at least 1 file from each sub-directory. (During installation, xCAT will define a yum or zypper repository for each directory you reference in your otherpkgs.pkglist.) For example: ::

    xcat/xcat-core/xCATsn
    xcat/xcat-dep/rh6/x86_64/conserver-xcat

There are some examples of otherpkgs.pkglist in /opt/xcat/share/xcat/netboot/<distro>/service.*.otherpkgs.pkglist that show the format.

Note: the otherpkgs postbootscript should by default be associated with every node. Use lsdef to check: ::

    lsdef node1 -i postbootscripts

If it is not, you need to add it. For example, add it for all of the nodes in the "compute" group: ::

    chdef -p -t group compute postbootscripts=otherpkgs

For the format of the .Otherpkgs file,see :ref:`File-Format-for-otherpkglist-label`

.. _File-Format-for-otherpkglist-label:

File Format for otherpkgs.pkglist File
--------------------------------------------------

The otherpkgs.pklist file can contain the following types of entries: ::

  * rpm name without version numbers 
  * otherpkgs subdirectory plus rpm name 
  * blank lines 
  * comment lines starting with # 
  * #INCLUDE: <full file path># to include other pkglist files 
  * #NEW_INSTALL_LIST# to signify that the following rpms will be installed with a new rpm install command (zypper, yum, or rpm as determined by the function using this file) 
  * #ENV:<variable list># to specify environment variable(s) for a sparate rpm install command 
  * rpms to remove before installing marked with a "-" 
  * rpms to remove after installing marked with a "--"

These are described in more details in the following sections.

RPM Names
~~~~~~~~~

A simple otherpkgs.pkglist file just contains the the name of the rpm file without the version numbers.

For example, if you put the following three rpms under /install/post/otherpkgs/<os>/<arch>/ directory, ::

    rsct.core-2.5.3.1-09120.ppc.rpm
    rsct.core.utils-2.5.3.1-09118.ppc.rpm
    src-1.3.0.4-09118.ppc.rpm

The otherpkgs.pkglist file will be like this: ::

    src
    rsct.core
    rsct.core.utils

RPM Names with otherpkgs Subdirectories
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you create a subdirectory under /install/post/otherpkgs/<os>/<arch>/, say rsct, the otherpkgs.pkglist file will be like this: ::

    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils

Include Other pkglist Files
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can group some rpms in a file and include that file in the otherpkgs.pkglist file using #INCLUDE:<file># format. ::

    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils
    #INCLUDE:/install/post/otherpkgs/myotherlist#

where /install/post/otherpkgs/myotherlist is another package list file that follows the same format.

Note the trailing "#" character at the end of the line. It is important to specify this character for correct pkglist parsing.

Multiple Install Lists
~~~~~~~~~~~~~~~~~~~~~~

The #NEW_INSTALL_LIST# statement is supported in xCAT 2.4 and later.

You can specify that separate calls should be made to the rpm install program (zypper, yum, rpm) for groups of rpms by specifying the entry #NEW_INSTALL_LIST# on a line by itself as a separator in your pkglist file. All rpms listed up to this separator will be installed together. You can have as many separators as you wish in your pkglist file, and each sublist will be installed separately in the order they appear in the file.

For example: ::

    compilers/vacpp.rte
    compilers/vac.lib
    compilers/vacpp.lib
    compilers/vacpp.rte.lnk
    #NEW_INSTALL_LIST#
    pe/IBM_pe_license

Environment Variable List
~~~~~~~~~~~~~~~~~~~~~~~~~~

The #ENV statement is supported on Redhat and SLES in xCAT 2.6.9 and later.

You can specify environment variable(s) for each rpm install call by entry "#ENV:<variable list>#". The environment variables also apply to rpm(s) remove call if there is rpm(s) needed to be removed in the sublist.

For example: ::

    #ENV:INUCLIENTS=1 INUBOSTYPE=1#
    rsct/rsct.core
    rsct/rsct.core.utils
    rsct/src

Be same as, ::

    #ENV:INUCLIENTS=1#
    #ENV:INUBOSTYPE=1#
    rsct/rsct.core
    rsct/rsct.core.utils
    rsct/src

Remove RPMs Before Installing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The "-" syntax is supported in xCAT 2.3 and later.

You can also specify in this file that certain rpms to be removed before installing the new software. This is done by adding '-' before the rpm names you want to remove. For example:

    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils
    #INCLUDE:/install/post/otherpkgs/myotherlist#
    -perl-doc

If you have #NEW_INSTALL_LIST# separators in your pkglist file, the rpms will be removed before the install of the sublist that the "-<rpmname>" appears in.

Remove RPMs After Installing
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The "--" syntax is supported in xCAT 2.3 and later.

You can also specify in this file that certain rpms to be removed after installing the new software. This is done by adding '--' before the rpm names you want to remove. For example:

    pe/IBM_pe_license
    --ibm-java2-ppc64-jre

If you have #NEW_INSTALL_LIST# separators in your pkglist file, the rpms will be removed after the install of the sublist that the "--<rpmname>" appears in. 

