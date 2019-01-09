
############
boottarget.7
############

.. highlight:: perl


****
NAME
****


\ **boottarget**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **boottarget Attributes:**\   \ *bprofile*\ , \ *comments*\ , \ *initrd*\ , \ *kcmdline*\ , \ *kernel*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


**********************
boottarget Attributes:
**********************



\ **bprofile**\  (boottarget.bprofile)
 
 All nodes with a nodetype.profile value equal to this value and nodetype.os set to "boottarget", will use the associated kernel, initrd, and kcmdline.
 


\ **comments**\  (boottarget.comments)
 
 Any user-written notes.
 


\ **initrd**\  (boottarget.initrd)
 
 The initial ramdisk image that network boot actions should use (could be a DOS floppy or hard drive image if using memdisk as kernel)
 


\ **kcmdline**\  (boottarget.kcmdline)
 
 Arguments to be passed to the kernel
 


\ **kernel**\  (boottarget.kernel)
 
 The kernel that network boot actions should currently acquire and use.  Note this could be a chained boot loader such as memdisk or a non-linux boot loader
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

