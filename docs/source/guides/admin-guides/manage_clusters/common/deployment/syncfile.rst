.. _Sync-Files-label:

Sync Files to Compute Node
=============================

Overview
--------

Synchronizing (sync) files to the nodes is a feature of xCAT used to distribute specific files from the management node to the new-deploying or deployed nodes.

This function is supported for diskfull or RAMdisk-based diskless nodes. **The function is not supported for NFS-based statelite nodes.** To sync files to statelite nodes you should use the read-only option for files/directories listed in litefile table with the source location specified in the litetree table. 

Generally, the specific files are usually the system configuration files for the nodes in the /etc/directory, like /etc/hosts, /etc/resolve.conf; it also could be the application programs configuration files for the nodes. The advantages of this function are: it can parallel sync files to the nodes or nodegroup for the installed nodes; it can automatically sync files to the newly-installing node after the installation. Additionally, this feature also supports the flexible format to define the synced files in a configuration file, called 'synclist'.

The synclist file can be a common one for a group of nodes using the same profile or osimage, or can be the special one for a particular node. Since the location of the synclist file will be used to find the synclist file, the common synclist should be put in a given location for Linux nodes or specified by the osimage.

xdcp command supplies the basic Syncing File function. If the '-F synclist' option is specified in the xdcp command, it syncs files configured in the synclist to the nodes. If the '-i PATH' option is specified with '-F synclist', it syncs files to the root image located in the PATH directory. (Note: the '-i PATH' option is only supported for Linux nodes)

xdcp supports hierarchy where service nodes are used. If a node is serviced by a service node, xdcp will sync the files to the service node first, then sync the files from service node to the compute node. The files are place in an intermediate directory on the service node defined by the SNsyncfiledir attribute in the site table. The default is /var/xcat/syncfiles.

Since 'updatenode -F' calls the xdcp to handle the Syncing File function, the 'updatenode -F' also supports the hierarchy.

For a new-installing nodes, the Syncing File action will be triggered when performing the postscripts for the nodes. A special postscript named 'syncfiles' is used to initiate the Syncing File process.

The postscript 'syncfiles' is located in the /install/postscripts/. When running, it sends a message to the xcatd on the management node or service node, then the xcatd figures out the corresponding synclist file for the node and calls the xdcp command to sync files in the synclist to the node.

If installing nodes in a hierarchical configuration, you must sync the Service Nodes first to make sure they are updated. The compute nodes will be sync'd from their service nodes.You can use the updatenode <computenodes> -f command to sync all the service nodes for range of compute nodes provided. ****

For an installed nodes, the Syncing File action happens when performing the 'updatenode -F' or 'xdcp -F synclist' command to update a nodes. If performing the 'updatenode -F', it figures out the location of the synclist files for all the nodes and classify the nodes which using same synclist file and then calls the 'xdcp -F synclist' to sync files to the nodes.


The synclist file
-----------------

The Format of synclist file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~
The synclist file contains the configuration entries that specify where the files should be synced to. In the synclist file, each line is an entry which describes the location of the source files and the destination location of files on the target node.

The basic entry format looks like following: ::

       path_of_src_file1 -> path_of_dst_file1
       path_of_src_file1 -> path_of_dst_directory ( must end in / if only one file to sync) 2.5 or later
       path_of_src_file1 path_of_src_file2 ... -> path_of_dst_directory

The path_of_src_file* should be the full path of the source file on the Management Node.

The path_of_dst_file* should be the full path of the destination file on target node.

The path_of_dst_directory should be the full path of the destination directory.

Since the synclist file is for common purpose, the target node need not be configured in it.

Example: the following synclist formats are supported:

sync file /etc/file2 to the file /etc/file2 on the node (with same file name) ::

       /etc/file2 -> /etc/file2

sync file /etc/file2 to the file /etc/file3 on the node (with different file name) ::
       
       /etc/file2 -> /etc/file3 

sync file /etc/file4 to the file /etc/tmp/file5 on the node( different file name and directory). The directory will be automatically created for you. ::

      /etc/file4 -> /etc/tmp/file5

sync the multiple files /etc/file1, /etc/file2, /etc/file3, ... to the directory /tmp/etc (/tmp/etc must be a directory when multiple files are synced at one time). If the directory does not exist,     xdcp will create it. ::
     
      /etc/file1 /etc/file2 /etc/file3 -> /tmp/etc

sync file /etc/file2 to the file /etc/file2 on the node ( with the same file name) (2.5 or later)  ::
 
       /etc/file2 -> /etc/

sync all files in /home/mikev to directory /home/mikev on the node (2.5 or later) ::

       /home/mikev/* -> /home/mikev/

Note: Don't try to sync files to the read only directory on the target node.


An example of synclist file
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Assume a user wants to sync files to a node as following, the corresponding entries should be added in a synclist file. 

Sync the file /etc/common_hosts to the two places on the target node: put one to the /etc/hosts, the other to the /tmp/etc/hosts. Following configuration entries should be added ::

       /etc/common_hosts -> /etc/hosts
       /etc/common_hosts -> /tmp/etc/hosts 
 
Sync files in the directory/tmp/prog1 to the directory /prog1 on the target node, and the postfix '.tmpl' needs to be removed on the target node. (directory /tmp/prog1/ contains two files: conf1.tmpl and conf2.tmpl) Following configuration entries should be added ::

       /tmp/prog1/conf1.tmpl -> /prog1/conf1
       /tmp/prog1/conf2.tmpl -> /prog1/conf2

Sync the files in the directory /tmp/prog2 to the directory /prog2 with same name on the target node. (directory /tmp/prog2 contains two files: conf1 and conf2) Following configuration entries should be added: ::
       
       /tmp/prog2/conf1 /tmp/prog2/conf2 -> /prog2

Sample synclist file ::
 
      /etc/common_hosts -> /etc/hosts
      /etc/common_hosts -> /tmp/etc/hosts
      /tmp/prog1/conf1.tmpl -> /prog1/conf1
      /tmp/prog1/conf2.tmpl -> /prog1/conf2
      /tmp/prog2/conf1 /tmp/prog2/conf2 -> /prog2
      /tmp/* -> /tmp/ ( 2.5 or later)
      /etc/testfile -> /etc/ ( 2.5 or later)    

If the above syncfile is performed by the updatenode/xdcp commands, or performed in a node installation process, the following files will exist on the target node with the following contents. ::
 
       /etc/hosts(It has the same content with /etc/common_hosts on the MN)
       /tmp/etc/hosts(It has the same content with /etc/common_hosts on the MN)
       /prog1/conf1(It has the same content with /tmp/prog1/conf1.tmpl on the MN)
       /prog1/conf2(It has the same content with /tmp/prog1/conf2.tmpl on the MN)
       /prog2/conf1(It has the same content with /tmp/prog2/conf1 on the MN)
       /prog2/conf2(It has the same content with /tmp/prog2/conf2 on the MN)

postscript support
~~~~~~~~~~~~~~~~~~

Putting the filename.post in the rsyncfile to rsync to the node is required for hierarchical clusters. It is optional for non-hierarchical cluster. 

Advanced synclist file features (EXECUTE, EXECUTEALWAYS,APPEND, MERGE)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

After you define the files to rsync in the syncfile, you can add an EXECUTEALWAYS clause in the syncfile. The EXECUTEALWAYS clause will list all the postscripts you would always like to run after the files are sync'd, whether or not any file is actually updated. The files in this list must be added to the list of files to rsync, if hierarchical. 

For example, your rsyncfile may look like this. Note: the path to the file to EXECUTE, is the location of the *.post file on the MN. ::


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

If /tmp/file2 is updated on the node in /tmp/file2, then /tmp/file2.post is automatically run on that node. If /tmp/file3 is updated on the node in /tmp/filex, then /tmp/file3.post is automatically run on that node.

You can add an APPEND clause to your syncfile.

The APPEND clause is used to append the contents of the input file to an existing file on the node. The file to be appended must already exist on the node and not be part of the synclist that contains the APPEND clause. 

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

When you use the APPEND clause, the file (left) of the arrow is appended to the file right of the arrow. In this example, /etc/myappenddir/appendfile is appended to /etc/mysetup/setup file, which must already exist on the node. The /opt/xcat/share/xcat/scripts/xdcpappend.sh is used to accomplish this.

The script creates a backup of the original file on the node in the directory defined by the site table nodesyncfiledir attribute, which is /var/xcat/node/syncfiles by default. To update the original file when using the function, you need to rsync a new original file to the node, removed the old original from the /var/xcat/node/syncfiles/org directory. If you want to cleanup all the files for the append function on the node, you can use the xdsh -c flag. See man page for xdsh.

Note:no order of execution may be assumed by the order that the EXECUTE,EXECUTEALWAYS and APPEND clause fall in the synclist file.

You can add an MERGE clause to your syncfile. This is only supported on Linux.

The MERGE clause is used to append the contents of the input file to either the /etc/passwd, /etc/shadow or /etc/group files. They are the only supported files. You must not put the /etc/passwd, /etc/shadow, /etc/group files in an APPEND clause if using a MERGE clause. For these three file you should use a MERGE clause. The APPEND will add the information to the end of the file. The MERGE will add or replace the information and insure that there are no duplicate entries in these files. 

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

When you use the MERGE clause, the file (left) of the arrow is merged into the file right of the arrow. It will replace any common userid's found in those files and add new userids. The /opt/xcat/share/xcat/scripts/xdcpmerge.sh is used to accomplish this. 

Note: no order of execution may be assumed by the order that the EXECUTE,EXECUTEALWAYS,APPEND and MERGE clause fall in the synclist file. 

.. _my-process-label:

The location of synclist file for updatenode and install process
-----------------------------------------------------------------

In the installation process or updatenode process, xCAT needs to figure out the location of the synclist file automatically, so the synclist should be put into the specified place with the proper name. 

If the provisioning method for the node is an osimage name, then the path to the synclist will be read from the osimage definition synclists attribute. You can display this information by running the following command, supplying your osimage name. ::

       lsdef -t osimage -l rhels6-x86_64-netboot-compute
       Object name: rhels6-x86_64-netboot-compute
       exlist=/opt/xcat/share/xcat/netboot/rhels6/compute.exlist
       imagetype=linux
       osarch=x86_64
       osname=Linux
       osvers=rhels6
       otherpkgdir=/install/post/otherpkgs/rhels6/x86_64
       pkgdir=/install/rhels6/x86_64
       pkglist=/opt/xcat/share/xcat/netboot/rhels6/compute.pkglist
       profile=compute
       provmethod=netboot
       rootimgdir=/install/netboot/rhels6/x86_64/compute
       **synclists=/install/custom/netboot/compute.synclist**

You can set the synclist path using the following command :: 

       chdef -t osimage -o  rhels6-x86_64-netboot-compute synclists="/install/custom/netboot/compute.synclist"

If the provisioning method for the node is install,or netboot then the path to the synclist should be of the following format ::

       /install/custom/&lt;inst_type&gt;/&lt;distro&gt;/&lt;profile&gt;.&lt;os&gt;.&lt;arch&gt;.synclist
       &lt;inst_type&gt;: "install", "netboot"
       &lt;distro&gt;: "rh", "centos", "fedora", "sles"
       &lt;profile&gt;,&lt;os&gt; and &lt;arch&gt; are what you set for the node

For example:
   The location of synclist file for the diskfull installation of sles11 with 'compute' as the profile ::

       /install/custom/install/sles/compute.sles11.synclist

The location of synclist file for the diskless netboot of sles11 with 'service' as the profile ::

       /install/custom/netboot/sles/service.sles11.synclist


Run xdcp command to perform Syncing File action
------------------------------------------------

xdcp command supplies three options '-F' , -s, and '-i' to support the Syncing File function.

   * -F|--File rsync input file

Specifies the full path to the synclist file that will be used to build the rsync command

    * -s

Specifies to rsync to the service nodes only for the input compute noderange.

    * -i|--rootimg install image for Linux

Specifies the full path to the install image on the local node. By default, if the -F option is specified, the 'rsync' command is used to perform the syncing file function. For the rsync in xdcp, only the ssh remote shell is supported for rsync.xdcp uses the '-Lpotz' as the default flags to call the rsync command. More flags for rsync command can be specified by adding '-o' flag to the call to xdcp.

For example: 

Using xdcp '-F' option to sync files which are listed in the /install/custom/commonsyncfiles/compute.synclist directory to the node group named 'compute'. If the node group compute is serviced by servicenodes, then the files will be automatically staged to the correct service nodes, and then synced to the compute nodes from those service nodes. The files will be stored in /var/xcat/syncfiles directory on the service nodes by default, or in the directory indicated in the site.SNsyncfiledir attribute. See -s option below. ::

       xdcp compute -F /install/custom/commonsynfiles/compute.synclist

For Linux nodes, using xdcp '-i' option with '-F' to sync files created in the /install/custom/install/sles11/compute.synclist to the osimage in the directory /install/netboot/sles11/ppc64/compute/rootimg: ::
      
       xdcp -i /install/netboot/sles11/ppc64/compute/rootimg -F /install/custom/install/sles11/compute.synclist     

Using the xdcp '-s' option to sync the files only to the service nodes for the node group named 'compute'. The files will be placed in the default /var/xcat/syncfiles directory or in the directory as indicated in the site.SNsyncfiledir attribute. If you want the files synched to the same directory on the service node that they come from on the Management Node, set site.SNsyncfiledir=/. This can be setup before a node install, to have the files available to be synced during the install: ::
   
     xdcp compute -s -F /install/custom/install/sles11/compute.synclist

Synchronizing Files during the installation process
----------------------------------------------------

The policy table must have the entry to allow syncfiles postscript to access the Management Node. Make sure this entry is in your table: ::

       tabdump policy
       #priority,name,host,commands,noderange,parameters,time,rule,comments,disable
       .
       .
       "4.6",,,"syncfiles",,,,"allow",,
       .
       .

Hierarchy and Service Nodes
~~~~~~~~~~~~~~~~~~~~~~~~~~~

If using Service nodes to manage you nodes, you should make sure that the service nodes have been synchronized with the latest files from the Management Node before installing. If you have a group of compute nodes (compute) that are going to be installed that are serviced by SN1, then run the following before the install to sync the current files to SN1. Note: the noderange is the compute node names, updatenode will figure out which service nodes need updating. ::

        updatenode compute -f

Diskfull installation
~~~~~~~~~~~~~~~~~~~~



The 'syncfiles' postscript is in the defaults section of the postscripts table. To enable the syn files postscript to sync files to the nodes during install the user need to do the following:

   * Create the synclist file with the entries indicating which files should be synced. Section 2.1 and 2.2 is a good example for how to create the synclist file.
   * Put the synclist into the proper location for the node type (refer :ref:`my-process-label`)
     
Make sure your postscripts table has the syncfiles postscript listed ::

       tabdump postscripts
       #node,postscripts,postbootscripts,comments,disable
       "xcatdefaults","syslog,remoteshell,syncfiles","otherpkgs",,

Diskless Installation
~~~~~~~~~~~~~~~~~~~~~

The diskless boot is similar with the diskfull installation for the synchronizing files operation, except that the packimage  commands will sync files to the root directories of image during the creating image process.

Creating the synclist file as the steps in Diskfull installation section, then the synced files will be synced to the os image during the packimage and mkdsklsnode commands running.

Also the files will always be re-synced during the booting up of the diskless node. 

Run the Sync'ing File action in the creating diskless image process
--------------------------------------------------------------------

Different approaches are used to create the diskless image. The Sync'ing File action is also different.

The packimage command is used to prepare the root image files and package the root image. The Syncing File action is performed here.

Steps to make the Sync'ing File working in the packimage command:

    Prepare the synclist file and put it into the appropriate location as describe above in
    Sync-ing_Config_Files_to_Nodes/#the-location-of-synclist-file-for-updatenode-and-install-process

    Run packimage as is normally done.

Run the Syncing File action in the updatenode process
------------------------------------------------------

If run updatenode command with -F option, it syncs files which configured in the synclist to the nodes. updatenode does not sync images, use xdcp -i -F option to sync images.

updatenode can be used to sync files to to diskfull or diskless nodes. updatenode cannot be used to sync files to statelite nodes.

Steps to make the Syncing File working in the 'updatenode -F' command:

   #. Create the synclist file with the entries indicating which files should be synced. (Section 2.1 and 2.2 is a good example for how to create the synclist file.)
   #. Put the synclist into the proper location (refer to part of section 2.3).
   #. Run the 'updatenode node -F' command to initiate the Syncing File action.

Note: Since Syncing File action can be initiated by the 'updatenode -F' flag, the 'updatenode -P' does NOT support to re-run the 'syncfiles' postscript, even if you specify the 'syncfiles' postscript in the updatenode command line or set the 'syncfiles' in the postscripts.postscripts attribute.

Run the Syncing File action periodically
-----------------------------------------

If the admins want to run the Syncing File action automatically or periodically, the 'xdcp -F', 'xdcp -i -F' and 'updatenode -F' commands can be used in the script, crontab or FAM directly.

For example:

Use the cron daemon to sync files in the /install/custom/install/sles/compute.sles11.synclist to the nodegroup 'compute' every 10 minutes by the xdcp command by adding this to crontab. : ::
      
       */10 * * * * root /opt/xcat/bin/xdcp compute -F /install/custom/install
       /sles/compute.sles11.synclist

Use the cron daemon to sync files for the nodegroup 'compute' every 10 minutes by updatenode command. ::

       */10 * * * * root /opt/xcat/bin/updatenode compute -F

** Related To do**








