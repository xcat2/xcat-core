
############
bootparams.5
############

.. highlight:: perl


****
NAME
****


\ **bootparams**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **bootparams Attributes:**\   \ *node*\ , \ *kernel*\ , \ *initrd*\ , \ *kcmdline*\ , \ *addkcmdline*\ , \ *dhcpstatements*\ , \ *adddhcpstatements*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Current boot settings to be sent to systems attempting network boot for deployment, stateless, or other reasons.  Mostly automatically manipulated by xCAT.


**********************
bootparams Attributes:
**********************



\ **node**\ 
 
 The node or group name
 


\ **kernel**\ 
 
 The kernel that network boot actions should currently acquire and use.  Note this could be a chained boot loader such as memdisk or a non-linux boot loader
 


\ **initrd**\ 
 
 The initial ramdisk image that network boot actions should use (could be a DOS floppy or hard drive image if using memdisk as kernel)
 


\ **kcmdline**\ 
 
 Arguments to be passed to the kernel
 


\ **addkcmdline**\ 
 
 User specified one or more parameters to be passed to the kernel. For the kernel options need to be persistent after installation, specify them with prefix "R::"
 


\ **dhcpstatements**\ 
 
 xCAT manipulated custom dhcp statements (not intended for user manipulation)
 


\ **adddhcpstatements**\ 
 
 Custom dhcp statements for administrator use (not implemneted yet)
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

