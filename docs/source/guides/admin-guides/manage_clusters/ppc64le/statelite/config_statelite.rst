Configuration
=============

Statelite configuration is done using the following tables in xCAT:
    * litefile 
    * litetree 
    * statelite 
    * policy 
    * noderes 

litefile table
--------------

The litefile table specifies the directories and files on the statelite nodes that should be read/write, persistent, or read-only overlay. All other files in the statelite nodes come from the read-only statelite image. 

#. The first column in the litefile table is the image name this row applies to. It can be an exact osimage definition name, an osimage group (set in the groups attribute of osimages), or the keyword ``ALL``.

#. The second column in the litefile table is the full path of the directory or file on the node that you are setting options for.

#. The third column in the litefile table specifies options for the directory or file: 

    #. tmpfs - It provides a file or directory for the node to use when booting, its permission will be the same as the original version on the server. In most cases, it is read-write; however, on the next statelite boot, the original version of the file or directory on the server will be used, it means it is non-persistent. This option can be performed on files and directories.
    #. rw - Same as Above.Its name "rw" does NOT mean it always be read-write, even in most cases it is read-write. Do not confuse it with the "rw" permission in the file system.
    #. persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted on the local file or directory. Anything written to that file or directory is preserved. It means, if the file/directory does not exist at first, it will be copied to the persistent location. Next time the file/directory in the persistent location will be used. The file/directory will be persistent across reboots. Its permission will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. This option can be performed on files and directories.
    #. con - The contents of the pathname are concatenated to the contents of the existing file. For this directive the searching in the litetree hierarchy does not stop when the first match is found. All files found in the hierarchy will be concatenated to the file when found. The permission of the file will be "-rw-r--r--", which means it is read-write for the root user, but readonly for the others. It is non-persistent, when the node reboots, all changes to the file will be lost. It can only be performed on files. Do not use it for one directory.
    #. ro - The file/directory will be overmounted read-only on the local file/directory. It will be located in the directory hierarchy specified in the litetree table. Changes made to this file or directory on the server will be immediately seen in this file/directory on the node. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. This option can be performed on files and directories.
    #. tmpfs,rw - Only for compatibility it is used as the default option if you leave the options column blank. It has the same semantics with the link option, so when adding new items into the _litefile table, the link option is recommended.
    #. link - It provides one file/directory for the node to use when booting, it is copied from the server, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to one file/directory in tmpfs. And the permission of the symbolic link is "lrwxrwxrwx", which is not the real permission of the file/directory on the node. So for some application sensitive to file permissions, it will be one issue to use "link" as its option, for example, "/root/.ssh/", which is used for SSH, should NOT use "link" as its option. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option can be performed on files and directories.
    #. link,ro - The file is readonly, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the tmpfs. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. The option can be performed on files and directories.
    #. link,con - Similar to the "con" option. All the files found in the litetree hierarchy will be concatenated to the file when found. The final file will be put to the tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the file/directory in tmpfs. It is non-persistent, when the node is rebooted, all changes to the file will be lost. The option can only be performed on files.
    #. link,persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted to the tmpfs on the booted node, and finally the symbolic link in the local file system will be linked to the over-mounted tmpfs file/directory on the booted node. The file/directory will be persistent across reboots. The permission of the file/directory where the symbolic link points to will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. The option can be performed on files and directories.
    #. localdisk - The file or directory will be stored in the local disk of the statelite node. Refer to the section To enable the localdisk option to enable the 'localdisk' support.

Currently, xCAT does not handle the relative links very well. The relative links are commonly used by the system libraries, for example, under ``/lib/`` directory, there will be one relative link matching one ``.so`` file. So, when you add one relative link to the litefile table (Not recommend), make sure the real file also be included, or put its directory name into the litefile table. 

**Note**: It is recommended that you specify at least the entries listed below in the litefile table, because most of these files need to be writeable for the node to boot up successfully. When any changes are made to their options, make sure they won't affect the whole system.

Sample Data for Redhat statelite setup
``````````````````````````````````````

This is the minimal list of files needed, you can add additional files to the litefile table. ::

    #image,file,options,comments,disable
    "ALL","/etc/adjtime","tmpfs",,
    "ALL","/etc/securetty","tmpfs",,
    "ALL","/etc/lvm/","tmpfs",,
    "ALL","/etc/ntp.conf","tmpfs",,
    "ALL","/etc/rsyslog.conf","tmpfs",,
    "ALL","/etc/rsyslog.conf.XCATORIG","tmpfs",,
    "ALL","/etc/udev/","tmpfs",,
    "ALL","/etc/ntp.conf.predhclient","tmpfs",,
    "ALL","/etc/resolv.conf","tmpfs",,
    "ALL","/etc/yp.conf","tmpfs",,
    "ALL","/etc/resolv.conf.predhclient","tmpfs",,
    "ALL","/etc/sysconfig/","tmpfs",,
    "ALL","/etc/ssh/","tmpfs",,
    "ALL","/etc/inittab","tmpfs",,
    "ALL","/tmp/","tmpfs",,
    "ALL","/var/","tmpfs",,
    "ALL","/opt/xcat/","tmpfs",,
    "ALL","/xcatpost/","tmpfs",,
    "ALL","/etc/systemd/system/multi-user.target.wants/","tmpfs",,
    "ALL","/root/.ssh/","tmpfs",,
    "ALL","/etc/rc3.d/","tmpfs",,
    "ALL","/etc/rc2.d/","tmpfs",,
    "ALL","/etc/rc4.d/","tmpfs",,
    "ALL","/etc/rc5.d/","tmpfs",,

Sample Data for SLES statelite setup
````````````````````````````````````

This is the minimal list of files needed, you can add additional files to the litefile table. ::

    #image,file,options,comments,disable
    "ALL","/etc/lvm/","tmpfs",,
    "ALL","/etc/ntp.conf","tmpfs",,
    "ALL","/etc/ntp.conf.org","tmpfs",,
    "ALL","/etc/resolv.conf","tmpfs",,
    "ALL","/etc/ssh/","tmpfs",,
    "ALL","/etc/sysconfig/","tmpfs",,
    "ALL","/etc/syslog-ng/","tmpfs",,
    "ALL","/etc/inittab","tmpfs",,
    "ALL","/tmp/","tmpfs",,
    "ALL","/etc/init.d/rc3.d/","tmpfs",,
    "ALL","/etc/init.d/rc5.d/","tmpfs",,
    "ALL","/var/","tmpfs",,
    "ALL","/etc/yp.conf","tmpfs",,
    "ALL","/etc/fstab","tmpfs",,
    "ALL","/opt/xcat/","tmpfs",,
    "ALL","/xcatpost/","tmpfs",,
    "ALL","/root/.ssh/","tmpfs",,

litetree table
--------------

The litetree table controls where the initial content of the files in the litefile table come from, and the long term content of the ``ro`` files. When a node boots up in statelite mode, it will by default copy all of its tmpfs files from the ``.default`` directory of the root image, for example ``/install/netboot/rhels7.3/x86_64/compute/rootimg/.default``, so there is not required to set up a litetree table. If you decide that you want some of the files pulled from different locations that are different per node, you can use this table.

You can choose to use the defaults and not set up a litetree table.

statelite table
---------------

The statelite table specifies location on an NFS server where a nodes persistent files are stored. This is done by entering the information into the statelite table.

In the statelite table, the node or nodegroups in the table must be unique; that is a node or group should appear only once in the first column table. This makes sure that only one statelite image can be assigned to a node. An example would be: ::

    "compute",,"<nfssvr_ip>:/gpfs/state",,

Any nodes in the compute node group will have their state stored in the ``/gpfs/state`` directory on the machine with ``<nfssvr_ip>`` as its IP address. 

When the node boots up, then the value of the ``statemnt`` attribute will be mounted to ``/.statelite/persistent``. The code will then create the following subdirectory ``/.statelite/persistent/<nodename>``, if there are persistent files that have been added in the litefile table. This directory will be the root of the image for this node's persistent files. By default, xCAT will do a hard NFS mount of the directory. You can change the mount options by setting the mntopts attribute in the statelite table.

Also, to set the ``statemnt`` attribute, you can use variables from xCAT database. It follows the same grammar as the litetree table. For example: ::

    #node,image,statemnt,mntopts,comments,disable
    "cn1",,"$noderes.nfsserver:/lite/state/$nodetype.profile","soft,timeo=30",,

``Note``: Do not name your persistent storage directory with the node name, as the node name will be added in the directory automatically. If you do, then a directory named ``/state/cn1`` will have its state tree inside ``/state/cn1/cn1``.

Policy
------

Ensure policies are set up correctly in the Policy Table. When a node boots up, it queries the xCAT database to get the litefile and litetree table information. In order for this to work, the commands (of the same name) must be set in the policy table to allow nodes to request it. This should happen automatically when xCAT is installed, but you may want to verify that the following lines are in the policy table: ::

    chdef -t policy -o 4.7 commands=litefile rule=allow
    chdef -t policy -o 4.8 commands=litetree rule=allow

noderes 
-------

``noderes.nfsserver`` attribute can be set for the NFSroot server. If this is not set, then the default is the Management Node.

``noderes.nfsdir`` can be set. If this is not set, the the default is ``/install``

