Overview
---------

The name of the packages that will be installed on the node are stored in the packages list files. There are two kinds of package list files:

* The package list file contains the names of the packages that comes from the os distro. They are stored in .pkglist file.
* The other package list file contains the names of the packages that do NOT come from the os distro. They are stored in .otherpkgs.pkglist file.

The path to the package lists will be read from the osimage definition. Which osimage a node is using is specified by the provmethod attribute. To display this value for a node: ::

     lsdef node1 -i provmethod 
     Object name: node
     provmethod=<osimagename>

You can display this details of this osimage by running the following command, supplying your osimage name: ::

        lsdef -t osimage <osimagename>
        Object name: <osimagename>
        exlist=/opt/xcat/share/xcat/<inst_type>/<os>/<profile>.exlist
        imagetype=linux
        osarch=<arch>
        osname=Linux
        osvers=<os>
        otherpkgdir=/install/post/otherpkgs/<os>/<arch>
        otherpkglist=/install/custom/<inst_type>/<distro>/<profile>.otherpkgs.pkglist
        pkgdir=/install/<os>/<arch>
        pkglist=/opt/xcat/share/xcat/<inst_type>/<os>/<profile>.pkglist
        postinstall=/opt/xcat/share/xcat/<inst_type>/<distro>/<profile>.<os>.<arch>.postinstall
        profile=<profile>
        provmethod=<profile>
        rootimgdir=/install/<inst_type>/<os>/<arch>/<profile>
        synclists=/install/custom/<inst_type>/<profile>.synclist

You can set the pkglist and otherpkglist using the following command: :: 

        chdef -t osimage <osimagename> pkglist=/opt/xcat/share/xcat/<inst_type>/<distro>/<profile>.pkglist\
                                                 otherpkglist=/install/custom/<inst_type>/<distro>/my.otherpkgs.pkglist


