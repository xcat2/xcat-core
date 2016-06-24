
#############
postscripts.5
#############

.. highlight:: perl


****
NAME
****


\ **postscripts**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **postscripts Attributes:**\   \ *node*\ , \ *postscripts*\ , \ *postbootscripts*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The scripts that should be run on each node after installation or diskless boot.


***********************
postscripts Attributes:
***********************



\ **node**\ 
 
 The node name or group name.
 


\ **postscripts**\ 
 
 Comma separated list of scripts that should be run on this node after diskful installation or diskless boot. Each script can take zero or more parameters. For example: "script1 p1 p2,script2,...". xCAT automatically adds the postscripts from  the xcatdefaults.postscripts attribute of the table to run first on the nodes after install or diskless boot. For installation of RedHat, CentOS, Fedora, the scripts will be run before the reboot. For installation of SLES, the scripts will be run after the reboot but before the init.d process. For diskless deployment, the scripts will be run at the init.d time, and xCAT will automatically add the list of scripts from the postbootscripts attribute to run after postscripts list. For installation of AIX, the scripts will run after the reboot and acts the same as the postbootscripts attribute.  For AIX, use the postbootscripts attribute.
 


\ **postbootscripts**\ 
 
 Comma separated list of scripts that should be run on this node after diskful installation or diskless boot. Each script can take zero or more parameters. For example: "script1 p1 p2,script2,...". On AIX these scripts are run during the processing of /etc/inittab.  On Linux they are run at the init.d time. xCAT automatically adds the scripts in the xcatdefaults.postbootscripts attribute to run first in the list.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

