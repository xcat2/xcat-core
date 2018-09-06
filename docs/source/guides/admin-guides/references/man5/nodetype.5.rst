
##########
nodetype.5
##########

.. highlight:: perl


****
NAME
****


\ **nodetype**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nodetype Attributes:**\   \ *node*\ , \ *os*\ , \ *arch*\ , \ *profile*\ , \ *provmethod*\ , \ *supportedarchs*\ , \ *nodetype*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


A few hardware and software characteristics of the nodes.


********************
nodetype Attributes:
********************



\ **node**\ 
 
 The node name or group name.
 


\ **os**\ 
 
 The operating system deployed on this node.  Valid values: AIX, rhels\*,rhelc\*, rhas\*,centos\*,SL\*, fedora\*, sles\* (where \* is the version #). As a special case, if this is set to "boottarget", then it will use the initrd/kernel/parameters specified in the row in the boottarget table in which boottarget.bprofile equals nodetype.profile.
 


\ **arch**\ 
 
 The hardware architecture of this node.  Valid values: x86_64, ppc64, x86, ia64.
 


\ **profile**\ 
 
 The string to use to locate a kickstart or autoyast template to use for OS deployment of this node.  If the provmethod attribute is set to an osimage name, that takes precedence, and profile need not be defined.  Otherwise, the os, profile, and arch are used to search for the files in /install/custom first, and then in /opt/xcat/share/xcat.
 


\ **provmethod**\ 
 
 The provisioning method for node deployment. The valid values are install, netboot, statelite or an os image name from the osimage table. If an image name is specified, the osimage definition stored in the osimage table and the linuximage table (for Linux) or nimimage table (for AIX) are used to locate the files for templates, pkglists, syncfiles, etc. On Linux, if install, netboot or statelite is specified, the os, profile, and arch are used to search for the files in /install/custom first, and then in /opt/xcat/share/xcat.
 


\ **supportedarchs**\ 
 
 Comma delimited list of architectures this node can execute.
 


\ **nodetype**\ 
 
 A comma-delimited list of characteristics of this node.  Valid values: ppc, blade, vm (virtual machine), osi (OS image), mm, mn, rsa, switch.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

