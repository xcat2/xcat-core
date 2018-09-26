
##########
nimimage.5
##########

.. highlight:: perl


****
NAME
****


\ **nimimage**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nimimage Attributes:**\   \ *imagename*\ , \ *nimtype*\ , \ *lpp_source*\ , \ *spot*\ , \ *root*\ , \ *dump*\ , \ *paging*\ , \ *resolv_conf*\ , \ *tmp*\ , \ *home*\ , \ *shared_home*\ , \ *res_group*\ , \ *nimmethod*\ , \ *script*\ , \ *bosinst_data*\ , \ *installp_bundle*\ , \ *mksysb*\ , \ *fb_script*\ , \ *shared_root*\ , \ *otherpkgs*\ , \ *image_data*\ , \ *configdump*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


All the info that specifies a particular AIX operating system image that can be used to deploy AIX nodes.


********************
nimimage Attributes:
********************



\ **imagename**\ 
 
 User provided name of this xCAT OS image definition.
 


\ **nimtype**\ 
 
 The NIM client type- standalone, diskless, or dataless.
 


\ **lpp_source**\ 
 
 The name of the NIM lpp_source resource.
 


\ **spot**\ 
 
 The name of the NIM SPOT resource.
 


\ **root**\ 
 
 The name of the NIM root resource.
 


\ **dump**\ 
 
 The name of the NIM dump resource.
 


\ **paging**\ 
 
 The name of the NIM paging resource.
 


\ **resolv_conf**\ 
 
 The name of the NIM resolv_conf resource.
 


\ **tmp**\ 
 
 The name of the NIM tmp resource.
 


\ **home**\ 
 
 The name of the NIM home resource.
 


\ **shared_home**\ 
 
 The name of the NIM shared_home resource.
 


\ **res_group**\ 
 
 The name of a NIM resource group.
 


\ **nimmethod**\ 
 
 The NIM install method to use, (ex. rte, mksysb).
 


\ **script**\ 
 
 The name of a NIM script resource.
 


\ **bosinst_data**\ 
 
 The name of a NIM bosinst_data resource.
 


\ **installp_bundle**\ 
 
 One or more comma separated NIM installp_bundle resources.
 


\ **mksysb**\ 
 
 The name of a NIM mksysb resource.
 


\ **fb_script**\ 
 
 The name of a NIM fb_script resource.
 


\ **shared_root**\ 
 
 A shared_root resource represents a directory that can be used as a / (root) directory by one or more diskless clients.
 


\ **otherpkgs**\ 
 
 One or more comma separated installp or rpm packages.  The rpm packages must have a prefix of 'R:', (ex. R:foo.rpm)
 


\ **image_data**\ 
 
 The name of a NIM image_data resource.
 


\ **configdump**\ 
 
 Specifies the type of system dump to be collected. The values are selective, full, and none.  The default is selective.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

