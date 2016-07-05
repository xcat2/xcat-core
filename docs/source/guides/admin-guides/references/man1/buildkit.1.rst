
##########
buildkit.1
##########

.. highlight:: perl


****
NAME
****


\ **buildkit**\  - Used to build a software product Kit which may be used to install software in an xCAT cluster.


********
SYNOPSIS
********


\ **buildkit**\  [\ **-? | -h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]

To build a new Kit

\ **buildkit**\  [\ **-V | -**\ **-verbose]**\  \ *subcommand*\  [\ *kit_name*\ ] [\ *repo_name*\  | \ **all**\ ] [\ **-l | -**\ **-kitloc**\  \ *kit_location*\ ]

To add packages to an existing Kit.

\ **buildkit**\  [\ **-V | -**\ **-verbose**\ ] \ *addpkgs*\  \ *kit_tarfile*\  [\ **-p | -**\ **-pkgdir**\  \ *package_directory_list*\ ] [\ **-k | -**\ **-kitversion**\  \ *version*\ ] [\ **-r | -**\ **-kitrelease**\  \ *release*\ ] [\ **-l | -**\ **-kitloc**\  \ *kit_location*\ ]


***********
DESCRIPTION
***********


The \ **buildkit**\  command provides a collection of utilities that may be used to package a software product as a Kit tarfile that can be used to install software on the nodes of an xCAT cluster.  A Kit contains the product software packages, configuration and control information, and install and customization scripts.

Note: The xCAT support for Kits is only available for Linux operating systems.

You will need to run the \ **buildkit**\  command several times with different subcommands to step through the process of building a kit:

By default the \ **buildkit**\  subcommands will operate in the current working directory, (ie. look for files, create directories etc.).  You could specify a different location by using the "\ **-l | -**\ **-kitloc**\  \ *kit_location*\ " option.

The \ *kit_location*\  is the full path name of the directory that contains the kit files. You would use the same location value for all the buildkit subcommands.

For example, to create a new kit named "prodkit" in the directory /home/mykits/ \ *either*\  run:


1.
 
 If no location is provided then the command will create a subdirectory called "prodkit" in the current directory "/home/mykits" and the new kit files will be created there.
 
 \ **cd /home/mykits**\ 
 
 \ **buildkit create prodkit**\ 
 
 or
 


2.
 
 If a location is provided then the Kit files will be created there. Note that the Kit name does not necessarily have to be the directory name where the kit files are located.
 
 \ **buidkit create prodkit -l /home/mykits/prodkit**\ 
 


In both cases the /home/mykits/prodkit directory is created and the inital files for the kit are created in that directory.

The following example illustrates the basic process for building a new Kit. In this example we are building a Kit named "mytstkit".


1.
 
 Change to the directory where you wish to create the Kit.
 


2.
 
 Create a template directory for your kit:
 
 \ **buildkit create mytstkit**\ 
 


3.
 
 Change directory to the new "mytstkit" subdirectory that was just created.
 
 \ **cd mytstkit**\ 
 


4.
 
 Edit the buildkit configuration file for your kit:
 
 \ **vi buildkit.conf**\ 
 
 (See xCAT Kit documentation for details.)
 


5.
 
 Create all required files, scripts, plugins, and packages for your kit.
 


6.
 
 Validate your kit build configuration and fix any errors that are reported:
 
 \ **buildkit chkconfig**\ 
 


7.
 
 List the repos defined in your buildkit configuration file:
 
 \ **buildkit listrepo**\ 
 


8.
 
 For each repo name listed, build the repository.  Note that if you need to build repositories for OS distributions, versions, or architectures that do not match the current system, you may need to copy your kit template directory to an appropriate server to build that repository, and then copy the results back to your main build server.  For example, to build a repo named "rhels6.3" you would run the following command.
 
 \ **buildkit buildrepo rhels6.3**\ 
 
 or, you can build all of the repos at one time if there are no OS or architecture dependencies for kitcomponent package builds or kitpackage builds:
 
 \ **buildkit buildrepo all**\ 
 


9.
 
 Build the kit tar file:
 
 \ **buildkit buildtar**\ 
 



*******
OPTIONS
*******



\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-k|-**\ **-kitversion**\  \ *version*\ 
 
 Product version.
 


\ **-l|-**\ **-kitloc**\  \ *kit_location*\ 
 
 The directory location of the Kit files.
 


\ **-p|-**\ **-pkgdir**\  \ *package_directory_list*\ 
 
 A comma-separated list of directory locations for product RPMs.
 


\ **-r|-**\ **-kitrelease**\  \ *release*\ 
 
 Product release.
 


\ **-V |-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 



************
SUB-COMMANDS
************



\ **create**\  \ *kit_basename*\ 
 
 Creates a new kit build directory structure for kit \ *kit_basename*\  using the location specified on the command line or the current directory.  The sample kit files from /opt/xcat/share/xcat/kits/kit_template are copied over, and the buildkit.conf file is modified for the specified \ *kit_basename*\ .
 


\ **chkconfig**\ 
 
 Reads the buildkit.conf file, verifies that the file syntax is correct and that all specified files exist.
 


\ **listrepo**\ 
 
 Reads the buildkit.conf file, lists all Kit package repositories listed in the file, and reports the build status for each repository.
 


\ **buildrepo**\  {\ *repo_name*\  | \ **all**\ }
 
 Reads the buildkit.conf file, and builds the specified Kit package repository.  The built packages are placed in the directory <kit_location>/build/kit_repodir/\ *repo_name*\ .  If \ **all**\  is specified, all kit repositories are built.
 


\ **cleanrepo**\  {\ *repo_name*\  | \ **all**\ }
 
 Reads the buildkit.conf file, and deletes all the package files and package meta data files from the <kit_location>/build/kit_repodir/\ *repo_name*\  directory.  If \ **all**\  is specified, all kit repository files are deleted.
 


\ **buildtar**\ 
 
 Reads the buildkit.conf file, validates that all kit repositories have been built, and builds the Kit tar file <kit_location>/\ *kitname*\ .tar.bz2.
 


\ **cleantar**\ 
 
 Reads the <kit_location>/buildkit.conf file and \ *deletes*\  the following:
 
 
 - Kit tar files matching <kit_location>/\ *kit_name\\*.tar.bz2*\ .
 
 - <kit_location>/build/\ *kit_name*\ 
 
 - <kit_location>/rpmbuild
 
 - <kit_location>/tmp
 
 - <kit_location>/debbuild
 
 Caution:  Make sure you back up any tar files you would like to keep before running this subcommand.
 


\ **cleanall**\ 
 
 Equivalent to running \ **buildkit cleanrepo all**\  and \ **buildkit cleantar**\ .
 


\ **addpkgs**\ 
 
 \ *kit_tarfile*\  {\ **-p**\  | \ **-**\ **-pkgdir**\  \ *package_directory_list*\ } [\ **-k**\  | \ **-**\ **-kitversion**\  \ *version*\ ] [\ **-r**\  | \ **-**\ **-kitrelease**\  \ *release*\ ]
 
 Add product package rpms to a previously built kit tar file.  This is used for partial product kits that are built and shipped separately from the product packages, and are identified with a \ *kit_tarfile*\  name of \ *kitname*\ .\ **NEED_PRODUCT_PKGS.tar.bz2**\ . Optionally, change the kit release and version values when building the new kit tarfile.  If kitcomponent version and/or release values are defaulted to the kit values, those will also be changed and new kitcomponent rpms will be built.  If kit or kitcomponent scripts, plugins, or other files specify name, release, or version substitution strings, these will all be replaced with the new values when built into the new complete kit tarfile \ *kit_location*\ /\ *new_kitname*\ .\ **tar.bz2**\ .
 



************
RETURN VALUE
************



<B>0
 
 The command completed successfully.
 


<B>1
 
 An error has occurred.
 



********
EXAMPLES
********



1.
 
 To create the sample kit shipped with the xCAT-buildkit rpm on a RHELS 6.3 server and naming it \ **mykit**\ , run the following commands:
 
 \ **cd /home/myuserid/kits**\ 
 
 \ **buildkit create mykit**\ 
 
 \ **cd mykit**\ 
 
 \ **vi buildkit.conf**\ 
 
 \ **buildkit chkconfig**\ 
 
 \ **buildkit listrepo**\ 
 
 \ **buildkit buildrepo all**\ 
 
 \ **buildkit buildtar**\ 
 


2.
 
 To clean up a kit repository directory after build failures on a RHELS 6.3 server to prepare for a new kit repository build, run:
 
 \ **buildkit cleanrepo rhels6.3**\ 
 


3.
 
 To clean up all kit build files, including a previously built kit tar file, run
 
 \ **buildkit cleanall**\ 
 


4.
 
 To create a kit named "tstkit" located in /home/foobar/tstkit instead of the current working directory.
 
 \ **buildkit create tstkit -l /home/foobar/tstkit**\ 
 



*****
FILES
*****


/opt/xcat/bin/buildkit

/opt/xcat/share/xcat/kits/kit_template

/opt/xcat/share/xcat/kits/kitcomponent.spec.template

<kit location>/buildkit.conf

<kit location>/build/\ *kitname*\ /kit.conf

<kit location>/\ *kitname*\ .tar.bz2


********
SEE ALSO
********


addkit(1), lskit(1), rmkit(1), addkitcomp(1), rmkitcomp(1), chkkitcomp(1)

