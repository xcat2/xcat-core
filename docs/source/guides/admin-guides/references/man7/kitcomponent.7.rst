
##############
kitcomponent.7
##############

.. highlight:: perl


****
NAME
****


\ **kitcomponent**\  - a logical object definition in the xCAT database.


********
SYNOPSIS
********


\ **kitcomponent Attributes:**\   \ *basename*\ , \ *description*\ , \ *driverpacks*\ , \ *exlist*\ , \ *genimage_postinstall*\ , \ *kitcompdeps*\ , \ *kitcompname*\ , \ *kitname*\ , \ *kitpkgdeps*\ , \ *kitreponame*\ , \ *postbootscripts*\ , \ *prerequisite*\ , \ *release*\ , \ *serverroles*\ , \ *version*\ 


***********
DESCRIPTION
***********


Logical objects of this type are stored in the xCAT database in one or more tables.  Use the following commands
to manipulate the objects: \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ , and \ **rmdef**\ .  These commands will take care of
knowing which tables the object attributes should be stored in.  The attribute list below shows, in
parentheses, what tables each attribute is stored in.


************************
kitcomponent Attributes:
************************



\ **basename**\  (kitcomponent.basename)
 
 Kit Component basename.
 


\ **description**\  (kitcomponent.description)
 
 The Kit component description.
 


\ **driverpacks**\  (kitcomponent.driverpacks)
 
 Comma-separated List of driver package names. These must be full names like: pkg1-1.0-1.x86_64.rpm.
 


\ **exlist**\  (kitcomponent.exlist)
 
 Exclude list file containing the files/directories to exclude when building a diskless image.
 


\ **genimage_postinstall**\  (kitcomponent.genimage_postinstall)
 
 Comma-separated list of postinstall scripts that will run during the genimage.
 


\ **kitcompdeps**\  (kitcomponent.kitcompdeps)
 
 Comma-separated list of kit components that this kit component depends on.
 


\ **kitcompname**\  (kitcomponent.kitcompname)
 
 The unique Kit Component name. It is auto-generated when the parent Kit is added to the cluster.
 


\ **kitname**\  (kitcomponent.kitname)
 
 The Kit name which this Kit Component belongs to.
 


\ **kitpkgdeps**\  (kitcomponent.kitpkgdeps)
 
 Comma-separated list of packages that this kit component depends on.
 


\ **kitreponame**\  (kitcomponent.kitreponame)
 
 The Kit Package Repository name which this Kit Component belongs to.
 


\ **postbootscripts**\  (kitcomponent.postbootscripts)
 
 Comma-separated list of postbootscripts that will run during the node boot.
 


\ **prerequisite**\  (kitcomponent.prerequisite)
 
 Prerequisite for this kit component, the prerequisite includes ospkgdeps,preinstall,preupgrade,preuninstall scripts
 


\ **release**\  (kitcomponent.release)
 
 Kit Component release.
 


\ **serverroles**\  (kitcomponent.serverroles)
 
 The types of servers that this Kit Component can install on.  Valid types are: mgtnode, servicenode, compute
 


\ **version**\  (kitcomponent.version)
 
 Kit Component version.
 



********
SEE ALSO
********


\ **mkdef(1)**\ , \ **chdef(1)**\ , \ **lsdef(1)**\ , \ **rmdef(1)**\ 

