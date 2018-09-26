
#######
iscsi.5
#######

.. highlight:: perl


****
NAME
****


\ **iscsi**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **iscsi Attributes:**\   \ *node*\ , \ *server*\ , \ *target*\ , \ *lun*\ , \ *iname*\ , \ *file*\ , \ *userid*\ , \ *passwd*\ , \ *kernel*\ , \ *kcmdline*\ , \ *initrd*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains settings that control how to boot a node from an iSCSI target


*****************
iscsi Attributes:
*****************



\ **node**\ 
 
 The node name or group name.
 


\ **server**\ 
 
 The server containing the iscsi boot device for this node.
 


\ **target**\ 
 
 The iscsi disk used for the boot device for this node.  Filled in by xCAT.
 


\ **lun**\ 
 
 LUN of boot device.  Per RFC-4173, this is presumed to be 0 if unset.  tgtd often requires this to be 1
 


\ **iname**\ 
 
 Initiator name.  Currently unused.
 


\ **file**\ 
 
 The path on the server of the OS image the node should boot from.
 


\ **userid**\ 
 
 The userid of the iscsi server containing the boot device for this node.
 


\ **passwd**\ 
 
 The password for the iscsi server containing the boot device for this node.
 


\ **kernel**\ 
 
 The path of the linux kernel to boot from.
 


\ **kcmdline**\ 
 
 The kernel command line to use with iSCSI for this node.
 


\ **initrd**\ 
 
 The initial ramdisk to use when network booting this node.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

