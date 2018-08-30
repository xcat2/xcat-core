
##############
kitcomponent.5
##############

.. highlight:: perl


****
NAME
****


\ **kitcomponent**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **kitcomponent Attributes:**\   \ *kitcompname*\ , \ *description*\ , \ *kitname*\ , \ *kitreponame*\ , \ *basename*\ , \ *version*\ , \ *release*\ , \ *serverroles*\ , \ *kitpkgdeps*\ , \ *prerequisite*\ , \ *driverpacks*\ , \ *kitcompdeps*\ , \ *postbootscripts*\ , \ *genimage_postinstall*\ , \ *exlist*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


This table stores all kit components added to the xCAT cluster.


************************
kitcomponent Attributes:
************************



\ **kitcompname**\ 
 
 The unique Kit Component name. It is auto-generated when the parent Kit is added to the cluster.
 


\ **description**\ 
 
 The Kit component description.
 


\ **kitname**\ 
 
 The Kit name which this Kit Component belongs to.
 


\ **kitreponame**\ 
 
 The Kit Package Repository name which this Kit Component belongs to.
 


\ **basename**\ 
 
 Kit Component basename.
 


\ **version**\ 
 
 Kit Component version.
 


\ **release**\ 
 
 Kit Component release.
 


\ **serverroles**\ 
 
 The types of servers that this Kit Component can install on.  Valid types are: mgtnode, servicenode, compute
 


\ **kitpkgdeps**\ 
 
 Comma-separated list of packages that this kit component depends on.
 


\ **prerequisite**\ 
 
 Prerequisite for this kit component, the prerequisite includes ospkgdeps,preinstall,preupgrade,preuninstall scripts
 


\ **driverpacks**\ 
 
 Comma-separated List of driver package names. These must be full names like: pkg1-1.0-1.x86_64.rpm.
 


\ **kitcompdeps**\ 
 
 Comma-separated list of kit components that this kit component depends on.
 


\ **postbootscripts**\ 
 
 Comma-separated list of postbootscripts that will run during the node boot.
 


\ **genimage_postinstall**\ 
 
 Comma-separated list of postinstall scripts that will run during the genimage.
 


\ **exlist**\ 
 
 Exclude list file containing the files/directories to exclude when building a diskless image.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

