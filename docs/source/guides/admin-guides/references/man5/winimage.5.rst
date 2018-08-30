
##########
winimage.5
##########

.. highlight:: perl


****
NAME
****


\ **winimage**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **winimage Attributes:**\   \ *imagename*\ , \ *template*\ , \ *installto*\ , \ *partitionfile*\ , \ *winpepath*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Information about a Windows operating system image that can be used to deploy cluster nodes.


********************
winimage Attributes:
********************



\ **imagename**\ 
 
 The name of this xCAT OS image definition.
 


\ **template**\ 
 
 The fully qualified name of the template file that is used to create the windows unattend.xml file for diskful installation.
 


\ **installto**\ 
 
 The disk and partition that the Windows will be deployed to. The valid format is <disk>:<partition>. If not set, default value is 0:1 for bios boot mode(legacy) and 0:3 for uefi boot mode; If setting to 1, it means 1:1 for bios boot and 1:3 for uefi boot
 


\ **partitionfile**\ 
 
 The path of partition configuration file. Since the partition configuration for bios boot mode and uefi boot mode are different, this configuration file can include both configurations if you need to support both bios and uefi mode. Either way, you must specify the boot mode in the configuration. Example of partition configuration file: [BIOS]xxxxxxx[UEFI]yyyyyyy. To simplify the setting, you also can set installto in partitionfile with section like [INSTALLTO]0:1
 


\ **winpepath**\ 
 
 The path of winpe which will be used to boot this image. If the real path is /tftpboot/winboot/winpe1/, the value for winpepath should be set to winboot/winpe1
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

