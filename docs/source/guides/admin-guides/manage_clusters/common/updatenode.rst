Using Updatenode
===================

Introduction
------------------

The xCAT platform-specific cookbooks explain how to initially deploy your nodes. After initial node deployment, you inevitably need to make changes/updates to your nodes. The updatenode command is for this purpose. It allows you to add or modify the following things on your nodes:

#. Add additional software
#. Synchronize new/updated configuration files
#. Rerun postscripts
#. Update ssh keys and xCAT certificates

Each of these will be explained in the document. The basic way to use updatenode is to set the definition of nodes on the management node the way you want it and then run updatenode to push those changes out to the actual nodes. Using options to the command, you can control which of the above categories updatenode pushes out to the nodes.

Most of what is described in this document applies to **stateful** and **stateless** nodes.
In addition to the information in this document, check out the updatenode man page.

Add Additional Software (Linux Only)
------------------------------------

The name of the rpms that will be installed on the node are stored in the packages list files. There are **two kinds of package list files**:

#. The **package list file** contains the names of the rpms that comes from the os distro. They are stored in **.pkglist** file.
#. The **other package list file** contains the names of the rpms that do **NOT** come from the os distro. They are stored in **.otherpkgs.pkglist** file.

The path to the package lists will be read from the osimage definition. Which osimage a node is using is specified by the provmethod attribute. To display this value for a node: ::

     lsdef node1 -i provmethod
     Object name: dx360m3n03
        provmethod=rhels6.3-x86_64-netboot-compute

You can display this details of this osimage by running the following command, supplying your osimage name: ::

    lsdef -t osimage rhels6.3-x86_64-netboot-compute
    Object name: rhels6.3-x86_64-netboot-compute
        exlist=/opt/xcat/share/xcat/netboot/rhels6.3/compute.exlist
        imagetype=linux
        osarch=x86_64
        osname=Linux
        osvers=rhels6.3
        otherpkgdir=/install/post/otherpkgs/rhels6.3/x86_64
        otherpkglist=/install/custom/netboot/rh/compute.otherpkgs.pkglist
        pkgdir=/install/rhels6/x86_64
        pkglist=/opt/xcat/share/xcat/netboot/rhels6/compute.pkglist
        postinstall=/opt/xcat/share/xcat/netboot/rh/compute.rhels6.x86_64.postinstall
        profile=compute
        provmethod=netboot
        rootimgdir=/install/netboot/rhels6.3/x86_64/compute
        synclists=/install/custom/netboot/compute.synclist

You can set the pkglist and otherpkglist using the following command: ::

     chdef -t osimage rhels6.3-x86_64-netboot-compute pkglist=/opt/xcat/share/xcat/netboot/rh/compute.pkglist\
    otherpkglist=/install/custom/netboot/rh/my.otherpkgs.pkglist

Installing Additional OS Distro Packages
----------------------------------------

For rpms from the OS distro, add the new rpm names (without the version number) in the .pkglist file. For example, file /install/custom/netboot/sles/compute.pkglist will look like this after adding perl-DBI::

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

If you have newer updates to some of your operating system packages that you would like to apply to your OS image, you can place them in another directory, and add that directory to your osimage pkgdir attribute. For example, with the osimage defined above, if you have a new openssl package that you need to update for security fixes, you could place it in a directory, create repository data, and add that directory to your pkgdir: ::

    mkdir -p /install/osupdates/rhels6.3/x86_64
    cd /install/osupdates/rhels6.3/x86_64
    cp <your new openssl rpm>  .
    createrepo .
    chdef -t osimage rhels6.3-x86_64-netboot-compute pkgdir=/install/rhels6/x86_64,/install/osupdates/rhels6.3/x86_64

Note:If the objective node is not installed by xCAT,please make sure the correct osimage pkgdir attribute so that you could get the correct repository data.

Install Additional non-OS rpms
------------------------------

Installing Additional Packages Using an Otherpkgs Pkglist
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you have additional rpms (rpms not in the distro) that you also want installed, make a directory to hold them, create a list of the rpms you want installed, and add that information to the osimage definition:

#. Create a directory to hold the additional rpms: ::

    mkdir -p /install/post/otherpkgs/rh/x86_64
    cd /install/post/otherpkgs/rh/x86_64
    cp /myrpms/* .
    createrepo .

    NOTE: when the management node is rhels6.x, and the otherpkgs repository data is for rhels5.x,
    we should run createrepo with "-s md5". Such as: ::

    createrepo -s md5 .

#. Create a file that lists the additional rpms that should be installed. For example, in /install/custom/netboot/rh/compute.otherpkgs.pkglist put: ::

    myrpm1
    myrpm2
    myrpm3

#. Add both the directory and the file to the osimage definition: ::

    chdef -t osimage mycomputeimage otherpkgdir=/install/post/otherpkgs/rh/x86_64 \
                       otherpkglist=/install/custom/netboot/rh/compute.otherpkgs.pkglist

  If you add more rpms at a later time, you must run createrepo again. The createrepo command is in the createrepo rpm, which for RHEL is in the 1st DVD, but for SLES is in the SDK DVD.

  If you have **multiple sets** of rpms that you want to **keep separate** to keep them organized, you can put them in separate sub-directories in the otherpkgdir:

  1. Run createrepo in each sub-directory.

  2. In your otherpkgs.pkglist, list at least 1 file from each sub-directory. (During installation,
     xCAT will define a yum or zypper repository for each directory you reference in your
     otherpkgs.pkglist.)

    For example: ::

     xcat/xcat-core/xCATsn
     xcat/xcat-dep/rh6/x86_64/conserver-xcat

  There are some examples of otherpkgs.pkglist in /opt/xcat/share/xcat/netboot/<distro>/service.*.otherpkgs.pkglist that show the format.

  Note: the otherpkgs postbootscript should by default be associated with every node. Use lsdef to check: ::

     lsdef node1 -i postbootscripts

  If it is not, you need to add it. For example, add it for all of the nodes in the "compute" group: ::

     chdef -p -t group compute postbootscripts=otherpkgs

  For the format of the .otherpkg.pklist file, go to Appendix_A:File_Format_for.pkglist_File


Update Stateful Nodes
^^^^^^^^^^^^^^^^^^^^^

Run the updatenode command to push the new software to the nodes: ::
    
    updatenode <noderange> -S
    

The -S flag updates the nodes with all the new or updated rpms specified in both .pkglist and .otherpkgs.pkglist. 

If you have a configuration script that is necessary to configure the new software, then instead run: ::
   
    cp myconfigscript /install/postscripts/
    chdef -p -t compute postbootscripts=myconfigscript
    updatenode <noderange> ospkgs,otherpkgs,myconfigscript
     

The next time you re-install these nodes, the additional software will be automatically installed. 

Update Stateless Nodes
^^^^^^^^^^^^^^^^^^^^^^

Run the updatenode command to push the new software to the nodes: ::
     
    updatenode <noderange> -S
    

The -S flag updates the nodes with all the new or updated rpms specified in both .pkglist and .otherpkgs.pkglist. 

If you have a configuration script that is necessary to configure the new software, then instead run: ::
  
    cp myconfigscript /install/postscripts/
    chdef -p -t compute postbootscripts=myconfigscript
    updatenode <noderange> ospkgs,otherpkgs,myconfigscript   

**You must also do this next step**, otherwise the next time you reboot the stateless nodes, the new software won't be on the nodes. Run genimage and packimage to install the extra rpms into the image: ::
 
    genimage <osimage>
    packimage <osimage>  

Update the delta changes in Sysclone environment
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Updatenode can also be used in Sysclone environment to push delta changes to target node. After capturing the delta changes from the golden client to management node, just run below command to push delta changes to target nodes. See **TODO:Using_Clone_to_Deploy_Server#Update_Nodes_Later_On_** for more information. ::

    updatenode <targetnoderange> -S

Rerun Postscripts or Run Additional Postcripts with the updatenode Command
--------------------------------------------------------------------------

You can use the updatenode command to perform the following functions after the nodes are up and running: 

  * Rerun postscripts defined in the postscripts table. You might want to do this, for example, if you changed database attributes that affect the running of the postscripts. 
  * Run any additional postscript one time. (If you want it run every time the node is deployed, you should add it to the postscript or postbootscript attribute of the nodes or node group.) The reason you might want to run a postscript on the nodes once, instead of running a script via xdsh or psh, is that the former approach will make a lot of environment variables available to the postscript that contain the node database values. See [[**TODO** :Postscripts_and_Prescripts]] for more information. 

To rerun all the postscripts for the nodes. (In general, xCAT postscripts are structured such that it is not harmful to run them multiple times.) ::
   
    updatenode <noderange> -P
   

To rerun just the syslog postscript for the nodes: ::
   
    updatenode <noderange> -P syslog   

To run a list of your own postscripts, make sure the scripts are copied to /install/postscripts directory, then: ::
   
    updatenode <noderange> -P "script1,script2"

If you need to, you can also pass arguments to your scripts (this will work in xCAT 2.6.7 and greater): ::
  
    updatenode <noderange> -P "script1 p1 p2,script2"
  
mypostscript template for updatenode

As of xCAT 2.8, you can customize what attributes you want made available to the post*script, using the shipped mypostscript.tmpl file. 

[[**TODO**:include ref=Template_of_mypostscript]] 

Update the ssh Keys and Credentials on the Nodes
------------------------------------------------

If after node deployment, the ssh keys or xCAT ssl credentials become corrupted, xCAT provides a way to quickly fix the keys and credentials on your Service and compute nodes: ::
   
     updatenode <noderange> -K    

Note: this option can't be used with any of the other updatenode options. 

syncfiles to the nodes
----------------------

If after install, you would like to sync files to the nodes, use the instructions in the next section on "Setting up syncfile for updatenode" and then run: ::
    
    updatenode <noderange> -F
   

**With the updatenode command the syncfiles postscript cannot be used to sync files to the nodes.** Therefore, if you run updatenode &lt;noderange&gt; -P syncfiles, nothing will be done. A messages will be logged that you must use updatenode &lt;noderange&gt; -F to sync files using updatenode. 

Setting up syncfile for updatenode
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

[[**TODO**:include ref=The_location_of_synclist_file_for_updatenode_and_install_process]] 

Appendix A: File Format for otherpkgs.pkglist File
--------------------------------------------------

The otherpkgs.pklist file can contain the following types of entries: 

  * rpm name without version numbers 
  * otherpkgs subdirectory plus rpm name 
  * blank lines 
  * comment lines starting with # 
  * #INCLUDE: <full file path># to include other pkglist files 
  * #NEW_INSTALL_LIST# to signify that the following rpms will be installed with a new rpm install command (zypper, yum, or rpm as determined by the function using this file) 
  * #ENV:<variable list># to specify environment variable(s) for a sperate rpm install command 
  * rpms to remove before installing marked with a "-" 
  * rpms to remove after installing marked with a "--" 

These are described in more details in the following sections. 

RPM Names
---------

A simple otherpkgs.pkglist file just contains the the name of the rpm file without the version numbers. 

For example, if you put the following three rpms under /install/post/otherpkgs/&lt;os&gt;/&lt;arch&gt;/ directory, ::
   
    rsct.core-2.5.3.1-09120.ppc.rpm
    rsct.core.utils-2.5.3.1-09118.ppc.rpm
    src-1.3.0.4-09118.ppc.rpm

The otherpkgs.pkglist file will be like this: ::
  
    src
    rsct.core
    rsct.core.utils 

RPM Names with otherpkgs Subdirectories
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you create a subdirectory under /install/post/otherpkgs/&lt;os&gt;/&lt;arch&gt;/, say rsct, the otherpkgs.pkglist file will be like this: ::
   
    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils

Include Other pkglist Files
^^^^^^^^^^^^^^^^^^^^^^^^^^^

You can group some rpms in a file and include that file in the otherpkgs.pkglist file using #INCLUDE:<file># format. ::
    
    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils
    #INCLUDE:/install/post/otherpkgs/myotherlist# 

where /install/post/otherpkgs/myotherlist is another package list file that follows the same format. 

Note the trailing "#" character at the end of the line. It is important to specify this character for correct pkglist parsing. 

Multiple Install Lists
^^^^^^^^^^^^^^^^^^^^^^

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
^^^^^^^^^^^^^^^^^^^^^^^^^

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
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The "-" syntax is supported in xCAT 2.3 and later.
  
You can also specify in this file that certain rpms to be removed before installing the new software. This is done by adding '-' before the rpm names you want to remove. For example: ::

    rsct/src
    rsct/rsct.core
    rsct/rsct.core.utils
    #INCLUDE:/install/post/otherpkgs/myotherlist#
    -perl-doc

  
If you have #NEW_INSTALL_LIST# separators in your pkglist file, the rpms will be removed before the install of the sublist that the "-<rpmname>" appears in. 

Remove RPMs After Installing
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The "--" syntax is supported in xCAT 2.3 and later.

You can also specify in this file that certain rpms to be removed after installing the new software. This is done by adding '--' before the rpm names you want to remove. For example: ::
  
    pe/IBM_pe_license
    --ibm-java2-ppc64-jre
  
If you have #NEW_INSTALL_LIST# separators in your pkglist file, the rpms will be removed after the install of the sublist that the "--<rpmname>" appears in. 

Appendix B: File Format for .pkglist File
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The .pklist file is used to specify the rpm and the group/pattern names from os distro that will be installed on the nodes. It can contain the following types of entries: ::

   * rpm name without version numbers 
   * group/pattern name marked with a '@' (for full install only) 
   * rpms to removed after the installation marked with a "-" (for full install only) 

These are described in more details in the following sections. 

RPM Names
^^^^^^^^^

A simple .pkglist file just contains the the name of the rpm file without the version numbers. 

For example, ::
  
    openssl
    xntp
    rsync
    glibc-devel.i686    

Include pkglist Files
^^^^^^^^^^^^^^^^^^^^^

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
^^^^^^^^^^^^^^^^^^^

It is only supported for statefull deployment. 

In Linux, a groups of rpms can be packaged together into one package. It is called a **group** on RedHat, CentOS, Fedora and Scientific Linux. To get the a list of available groups, run ::
   
    yum grouplist    

On SLES, it is called a **pattern**. To list all the available patterns, run :: 
    
    zypper se -t pattern    
  
You can specify in this file the group/pattern names by adding a '@' and a space before the group/pattern names. For example: ::
   
    @ base

Remove RPMs After Installing
^^^^^^^^^^^^^^^^^^^^^^^^^^^^

It is only supported for statefull deployment. 

You can specify in this file that certain rpms to be removed after installing the new software. This is done by adding '-' before the rpm names you want to remove. For example: ::
   
    wget   

Appendix C: Debugging Tips
--------------------------

Internally updatenode command uses the xdsh in the following ways: 

Linux: xdsh <noderange> -e /install/postscripts/xcatdsklspost -m <server> <scripts&gt>

AIX: xdsh <noderange> -e /install/postscripts/xcataixspost -m <server> -c 1 <scripts>

where <scripts> is a comma separated postscript like ospkgs,otherpkgs etc. 

  * wget is used in xcatdsklspost/xcataixpost to get all the postscripts from the <server> to the node. You can check /tmp/wget.log file on the node to see if wget was successful or not. You need to make sure the  /xcatpost directory has enough space to hold the postscripts. 
  * A file called /xcatpost/mypostscript (Linux) or /xcatpost/myxcatpost_<node> (AIX) is created on the node which contains the environmental variables and scripts to be run. Please make sure this file exists and it contains correct info. You can also run this file on the node manually to debug. 
  * For ospkgs/otherpkgs, if /install is not mounted on the <server>, it will download all the rpms from the <server> to the node using wget. Please make sure /tmp and /xcatpost have enough space to hold the rpms and please check /tmp/wget.log for errors. 
  * For ospkgs/otherpkgs, If zypper or yum is installed on the node, it will be used the command to install the rpms. Please make sure to run createrepo on the source direcory on the <server> every time a rpm is added or removed. Otherwise, the rpm command will be used, in this case, please make sure all the necessary depended rpms are copied in the same source directory. 
  * You can append -x on the first line of ospkgs/otherpkgs to get more debug info. 

