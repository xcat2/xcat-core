.. _Install-Additional-OS-Packages-label:

Install Additional OS Packages for RHEL and SLES
------------------------------------------------

Install Additional Packages using OS Packages steps
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

For rpms from the OS distro, add the new rpm names (without the version number) in the .pkglist file. For example, file **/install/custom/<inst_type>/<os>/<profile>.pkglist** will look like this after adding perl-DBI: ::

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

If you have newer updates to some of your operating system packages that you would like to apply to your **OS** image, you can place them in another directory, and add that directory to your osimage pkgdir attribute. For example, with the osimage defined above, if you have a new openssl package that you need to update for security fixes, you could place it in a directory, create repository data, and add that directory to your pkgdir: ::

       mkdir -p /install/osupdates/<os>/<arch>
       cd /install/osupdates/<os>/<arch>
       cp <your new openssl rpm>  .
       createrepo .
       chdef -t osimage <os>-<arch>-<inst_type>-<profile> pkgdir=/install/<os>/<arch>,/install/osupdates/<os>/<arch>

Note:If the objective node is not installed by xCAT, make sure the correct osimage pkgdir attribute so that you could get the correct repository data.

.. _File-Format-for-pkglist-label:

File Format for .ospkgs.pkglist File
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The .pklist file is used to specify the rpm and the group/pattern names from os distro that will be installed on the nodes. It can contain the following types of entries: ::

  * rpm name without version numbers
  * group/pattern name marked with a '@' (for full install only)
  * rpms to removed after the installation marked with a "-" (for full install only)

These are described in more details in the following sections.

RPM Names
''''''''''

A simple .pkglist file just contains the the name of the rpm file without the version numbers.

For example  ::

    openssl
    xntp
    rsync
    glibc-devel.i686

Include pkglist Files
''''''''''''''''''''''

The **#INCLUDE** statement is supported in the pkglist file.

You can group some rpms in a file and include that file in the pkglist file using **#INCLUDE:<file>#** format. ::

    openssl
    xntp
    rsync
    glibc-devel.1686
    #INCLUDE:/install/post/custom/<distro>/myotherlist#

where **/install/post/custom/<distro>/myotherlist** is another package list file that follows the same format.

Note: the trailing **"#"** character at the end of the line. It is important to specify this character for correct pkglist parsing.

Group/Pattern Names
'''''''''''''''''''

It is only supported for stateful deployment.

In Linux, a groups of rpms can be packaged together into one package. It is called a group on RedHat, CentOS, Fedora and Scientific Linux. To get the a list of available groups, run 

* **[RHEL]** ::

   yum grouplist

* **[SLES]** ::

   zypper se -t pattern

You can specify in this file the group/pattern names by adding a **'@'** and a space before the group/pattern names. For example: ::

    @ base

Remove RPMs After Installing
''''''''''''''''''''''''''''

It is only supported for stateful deployment.

You can specify in this file that certain rpms to be removed after installing the new software. This is done by adding **'-'** before the rpm names you want to remove. For example: ::

    -ntp

