.. _The_synclist_file:

The synclist file
-----------------

.. _The_Format_of_synclist_file_label:

The Format of synclist file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The synclist file contains the configuration entries that specify where the files should be synced to. In the synclist file, each line is an entry which describes the location of the source files and the destination location of files on the target node.

The basic entry format looks like following: ::

       path_of_src_file1 -> path_of_dst_file1
       path_of_src_file1 -> path_of_dst_directory 
       path_of_src_file1 path_of_src_file2 ... -> path_of_dst_directory

The path_of_src_file* should be the full path of the source file on the Management Node.

The path_of_dst_file* should be the full path of the destination file on target node.

The path_of_dst_directory should be the full path of the destination directory.

Since the synclist file is for common purpose, the target node need not be configured in it.

Example: the following synclist formats are supported:

sync file **/etc/file2** to the file **/etc/file2** on the node (with same file name) ::

       /etc/file2 -> /etc/file2

sync file **/etc/file2** to the file **/etc/file3** on the node (with different file name) ::
       
       /etc/file2 -> /etc/file3 

sync file **/etc/file4** to the file **/etc/tmp/file5** on the node( different file name and directory). The directory will be automatically created for you. ::

      /etc/file4 -> /etc/tmp/file5

sync the multiple files **/etc/file1**, **/etc/file2**, **/etc/file3**, ... to the directory **/tmp/etc** (**/tmp/etc** must be a directory when multiple files are synced at one time). If the directory does not exist,**xdcp** will create it. ::
     
      /etc/file1 /etc/file2 /etc/file3 -> /tmp/etc

sync file **/etc/file2** to the file /etc/file2 on the node   ::
 
       /etc/file2 -> /etc/

sync all files in **/home/mikev** to directory **/home/mikev** on the node  ::

       /home/mikev/* -> /home/mikev/

Note: Don't try to sync files to the read only directory on the target node.

An example of synclist file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Assume a user wants to sync files to a node as following, the corresponding entries should be added in a synclist file. 

Sync the file **/etc/common_hosts** to the two places on the target node: put one to the **/etc/hosts**, the other to the **/tmp/etc/hosts**. Following configuration entries should be added ::

       /etc/common_hosts -> /etc/hosts
       /etc/common_hosts -> /tmp/etc/hosts 
 
Sync files in the directory **/tmp/prog1** to the directory **/prog1** on the target node, and the postfix **'.tmpl'** needs to be removed on the target node. (directory **/tmp/prog1/** contains two files: **conf1.tmpl** and **conf2.tmpl**) Following configuration entries should be added ::

       /tmp/prog1/conf1.tmpl -> /prog1/conf1
       /tmp/prog1/conf2.tmpl -> /prog1/conf2

Sync the files in the directory **/tmp/prog2** to the directory **/prog2** with same name on the target node. (directory **/tmp/prog2** contains two files: **conf1** and **conf2**) Following configuration entries should be added: ::
       
       /tmp/prog2/conf1 /tmp/prog2/conf2 -> /prog2

Sample synclist file ::
 
      /etc/common_hosts -> /etc/hosts
      /etc/common_hosts -> /tmp/etc/hosts
      /tmp/prog1/conf1.tmpl -> /prog1/conf1
      /tmp/prog1/conf2.tmpl -> /prog1/conf2
      /tmp/prog2/conf1 /tmp/prog2/conf2 -> /prog2
      /tmp/* -> /tmp/ 
      /etc/testfile -> /etc/     

If the above syncfile is performed by the **updatenode/xdcp** commands, or performed in a node installation process, the following files will exist on the target node with the following contents. ::
 
       /etc/hosts(It has the same content with /etc/common_hosts on the MN)
       /tmp/etc/hosts(It has the same content with /etc/common_hosts on the MN)
       /prog1/conf1(It has the same content with /tmp/prog1/conf1.tmpl on the MN)
       /prog1/conf2(It has the same content with /tmp/prog1/conf2.tmpl on the MN)
       /prog2/conf1(It has the same content with /tmp/prog2/conf1 on the MN)
       /prog2/conf2(It has the same content with /tmp/prog2/conf2 on the MN)


Support nodes in synclist file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Note: From xCAT 2.9.2 on AIX and from xCAT 2.12 on Linux, xCAT support a new format for syncfile. The new format is  ::

       file -> (noderange for permitted nodes) file

The noderange would have several format. Following examples show that /etc/hosts file is synced to the nodes which is specifed before the file name  ::

       /etc/hosts -> (node1,node2) /etc/hosts            # The /etc/hosts file is synced to node1 and node2
       /etc/hosts -> (node1-node4) /etc/hosts            # The /etc/hosts file is synced to node1,node2,node3 and node4
       /etc/hosts -> (node[1-4]) /etc/hosts              # The /etc/hosts file is synced to node1, node2, node3 and node4
       /etc/hosts -> (node1,node[2-3],node4) /etc/hosts  # The /etc/hosts file is synced to node1, node2, node3 and node4
       /etc/hosts -> (group1) /etc/hosts                 # The /etc/hosts file is synced to nodes in group1
       /etc/hosts -> (group1,group2) /etc/hosts          #  The /etc/hosts file is synced to nodes in group1 and group2

postscript support
~~~~~~~~~~~~~~~~~~

Putting the filename.post in the **rsyncfile** to ``rsync`` to the node is required for hierarchical clusters. It is optional for non-hierarchical cluster. 

Advanced synclist file features 
''''''''''''''''''''''''''''''''''

After you define the files to rsync in the syncfile, you can add an **EXECUTEALWAYS** clause in the syncfile. The **EXECUTEALWAYS** clause will list all the postscripts you would always like to run after the files are sync'd, whether or not any file is actually updated. The files in this list must be added to the list of files to rsync, if hierarchical. 

For example, your rsyncfile may look like this. **Note: the path to the file to EXECUTE, is the location of the *.post file on the MN**. ::


       /tmp/share/file2  -> /tmp/file2
       /tmp/share/file2.post -> /tmp/file2.post (required for hierarchical clusters)
       /tmp/share/file3 -> /tmp/file3
       /tmp/share/file3.post -> /tmp/file3.post (required for hierarchical clusters)
       /tmp/myscript1 -> /tmp/myscript1
       /tmp/myscript2 -> /tmp/myscript2
       # the below are postscripts
       EXECUTE:
       /tmp/share/file2.post
       /tmp/share/file3.post
       EXECUTEALWAYS:  
       /tmp/myscript1
       /tmp/myscript2 

If **/tmp/file2** is updated on the node in **/tmp/file2**, then **/tmp/file2**.post is automatically run on that node. If **/tmp/file3** is updated on the node in **/tmp/filex**, then **/tmp/file3**.post is automatically run on that node.

You can add an **APPEND** clause to your syncfile.

The **APPEND** clause is used to append the contents of the input file to an existing file on the node. The file to be appended must already exist on the node and not be part of the synclist that contains the **APPEND** clause. 

For example, your synclist file may look like this: ::

       /tmp/share/file2  ->  /tmp/file2
       /tmp/share/file2.post -> /tmp/file2.post
       /tmp/share/file3  ->  /tmp/filex
       /tmp/share/file3.post -> /tmp/file3.post
       /tmp/myscript -> /tmp/myscript
       # the below are postscripts
       EXECUTE:
       /tmp/share/file2.post
       /tmp/share/file3.post
       EXECUTEALWAYS:
       /tmp/myscript
       APPEND:
       /etc/myappenddir/appendfile -> /etc/mysetup/setup
       /etc/myappenddir/appendfile2 -> /etc/mysetup/setup2

When you use the **APPEND** clause, the file (left) of the arrow is appended to the file right of the arrow. In this example, **/etc/myappenddir/appendfile** is appended to **/etc/mysetup/setup** file, which must already exist on the node. The **/opt/xcat/share/xcat/scripts/xdcpappend.sh** is used to accomplish this.

The script creates a backup of the original file on the node in the directory defined by the site table nodesyncfiledir attribute, which is **/var/xcat/node/syncfiles** by default. To update the original file when using the function, you need to rsync a new original file to the node, removed the old original from the **/var/xcat/node/syncfiles/org** directory. If you want to cleanup all the files for the append function on the node, you can use the ``xdsh -c`` flag. See man page for ``xdsh``.

Note:no order of execution may be assumed by the order that the **EXECUTE,EXECUTEALWAYS and APPEND** clause fall in the synclist file.

You can add an **MERGE** clause to your syncfile. This is only supported on Linux.

The **MERGE** clause is used to append the contents of the input file to either the **/etc/passwd**, **/etc/shadow** or **/etc/group** files. They are the only supported files. You must not put the **/etc/passwd**, **/etc/shadow**, **/etc/group** files in an **APPEND** clause if using a **MERGE** clause. For these three file you should use a **MERGE** clause. The **APPEND** will add the information to the end of the file. The **MERGE** will add or replace the information and insure that there are no duplicate entries in these files. 

For example, your synclist file may look like this ::

       /tmp/share/file2  ->  /tmp/file2
       /tmp/share/file2.post -> /tmp/file2.post
       /tmp/share/file3  ->  /tmp/filex
       /tmp/share/file3.post -> /tmp/file3.post
       /tmp/myscript -> /tmp/myscript
       # the below are postscripts
       EXECUTE:
       /tmp/share/file2.post
       /tmp/share/file3.post
       EXECUTEALWAYS:
       /tmp/myscript
       MERGE:
       /etc/mydir/mergepasswd -> /etc/passwd
       /etc/mydir/mergeshadow -> /etc/shadow
       /etc/mydir/mergegroup -> /etc/group

When you use the **MERGE** clause, the file (left) of the arrow is merged into the file right of the arrow. It will replace any common userid's found in those files and add new userids. The /opt/xcat/share/xcat/scripts/xdcpmerge.sh is used to accomplish this. 

Note: no order of execution may be assumed by the order that the **EXECUTE,EXECUTEALWAYS,APPEND and MERGE** clause fall in the synclist file. 

.. _the_localtion_of_synclist_file_for_updatenode_label:

The location of synclist file for updatenode and install process
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

In the installation process or updatenode process, xCAT needs to figure out the location of the synclist file automatically, so the synclist should be put into the specified place with the proper name. 

If the provisioning method for the node is an osimage name, then the path to the synclist will be read from the osimage definition synclists attribute. You can display this information by running the following command, supplying your osimage name. ::

       lsdef -t osimage -l <os>-<arch>-netboot-compute
       Object name: <os>-<arch>-netboot-compute
       exlist=/opt/xcat/share/xcat/netboot/<os>/compute.exlist
       imagetype=linux
       osarch=<arch>
       osname=Linux
       osvers=<os>
       otherpkgdir=/install/post/otherpkgs/<os>/<arch>
       pkgdir=/install/<os>/<arch>
       pkglist=/opt/xcat/share/xcat/netboot/<os>/compute.pkglist
       profile=compute
       provmethod=netboot
       rootimgdir=/install/netboot/<os>/<arch>/compute
       **synclists=/install/custom/netboot/compute.synclist**

You can set the synclist path using the following command :: 

       chdef -t osimage -o  <os>-<arch>-netboot-compute synclists="/install/custom/netboot/compute.synclist

If the provisioning method for the node is install,or netboot then the path to the synclist should be of the following format ::

       /install/custom/<inst_type>/<distro>/<profile>.<os>.<arch>.synclist
       <inst_type>: "install", "netboot"
       <distro>:    "rh", "centos", "fedora", "sles"
       <profile>,<os>and <arch> are what you set for the node

For example:
The location of synclist file for the diskful installation of <os> with 'compute' as the profile ::

       /install/custom/<inst_type>/<distro>/<profile>.<os>.synclist

The location of synclist file for the diskless netboot of <os> with '<profile>' as the profile ::

       /install/custom/<inst_type>/<distro>/<profile>.<os>.synclist


