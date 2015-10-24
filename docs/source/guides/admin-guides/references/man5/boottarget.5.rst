
############
boottarget.5
############

.. highlight:: perl


****
NAME
****


\ **boottarget**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **boottarget Attributes:**\   \ *bprofile*\ , \ *kernel*\ , \ *initrd*\ , \ *kcmdline*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Specify non-standard initrd, kernel, and parameters that should be used for a given profile.


**********************
boottarget Attributes:
**********************



\ **bprofile**\ 
 
 All nodes with a nodetype.profile value equal to this value and nodetype.os set to "boottarget", will use the associated kernel, initrd, and kcmdline.
 


\ **kernel**\ 
 
 The kernel that network boot actions should currently acquire and use.  Note this could be a chained boot loader such as memdisk or a non-linux boot loader
 


\ **initrd**\ 
 
 The initial ramdisk image that network boot actions should use (could be a DOS floppy or hard drive image if using memdisk as kernel)
 


\ **kcmdline**\ 
 
 Arguments to be passed to the kernel
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

