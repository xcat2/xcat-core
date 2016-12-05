
##########
litefile.5
##########

.. highlight:: perl


****
NAME
****


\ **litefile**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **litefile Attributes:**\   \ *image*\ , \ *file*\ , \ *options*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The litefile table specifies the directories and files on the statelite nodes that should be readwrite, persistent, or readonly overlay.  All other files in the statelite nodes come from the readonly statelite image.


********************
litefile Attributes:
********************



\ **image**\ 
 
 The name of the image (as specified in the osimage table) that will use these options on this dir/file. You can also specify an image group name that is listed in the osimage.groups attribute of some osimages. 'ALL' means use this row for all images.
 


\ **file**\ 
 
 The full pathname of the file. e.g: /etc/hosts.  If the path is a directory, then it should be terminated with a '/'.
 


\ **options**\ 
 
 Options for the file:
 
 
 .. code-block:: perl
 
   tmpfs - It is the default option if you leave the options column blank. It provides a file or directory for the node to use when booting, its permission will be the same as the original version on the server. In most cases, it is read-write; however, on the next statelite boot, the original version of the file or directory on the server will be used, it means it is non-persistent. This option can be performed on files and directories..
  
   rw - Same as above. Its name "rw" does NOT mean it always be read-write, even in most cases it is read-write. Do not confuse it with the "rw" permission in the file system. 
  
   persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted on the local file or directory. Anything written to that file or directory is preserved. It means, if the file/directory does not exist at first, it will be copied to the persistent location. Next time the file/directory in the persistent location will be used. The file/directory will be persistent across reboots. Its permission will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. This option can be performed on files and directories. 
  
   con - The contents of the pathname are concatenated to the contents of the existing file. For this directive the searching in the litetree hierarchy does not stop when the first match is found. All files found in the hierarchy will be concatenated to the file when found. The permission of the file will be "-rw-r--r--", which means it is read-write for the root user, but readonly for the others. It is non-persistent, when the node reboots, all changes to the file will be lost. It can only be performed on files. Do not use it for one directory.
  
   ro - The file/directory will be overmounted read-only on the local file/directory. It will be located in the directory hierarchy specified in the litetree table. Changes made to this file or directory on the server will be immediately seen in this file/directory on the node. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. This option can be performed on files and directories.
  
   link - It provides one file/directory for the node to use when booting, it is copied from the server, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to one file/directory in tmpfs. And the permission of the symbolic link is "lrwxrwxrwx", which is not the real permission of the file/directory on the node. So for some application sensitive to file permissions, it will be one issue to use "link" as its option, for example, "/root/.ssh/", which is used for SSH, should NOT use "link" as its option. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option can be performed on files and directories. 
  
   link,con -  It works similar to the "con" option. All the files found in the litetree hierarchy will be concatenated to the file when found. The final file will be put to the tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the file/directory in tmpfs. It is non-persistent, when the node is rebooted, all changes to the file will be lost. The option can only be performed on files. 
  
    link,persistent - It provides a mounted file or directory that is copied to the xCAT persistent location and then over-mounted to the tmpfs on the booted node, and finally the symbolic link in the local file system will be linked to the over-mounted tmpfs file/directory on the booted node. The file/directory will be persistent across reboots. The permission of the file/directory where the symbolic link points to will be the same as the original one in the statelite location. It requires the statelite table to be filled out with a spot for persistent statelite. The option can be performed on files and directories.
  
   link,ro - The file is readonly, and will be placed in tmpfs on the booted node. In the local file system of the booted node, it is one symbolic link to the tmpfs. It is non-persistent, when the node is rebooted, all changes to the file/directory will be lost. This option requires that the file/directory to be mounted must be available in one of the entries in the litetree table. The option can be performed on files and directories.
 
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

