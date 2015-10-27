
########
cfgmgt.5
########

.. highlight:: perl


****
NAME
****


\ **cfgmgt**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **cfgmgt Attributes:**\   \ *node*\ , \ *cfgmgr*\ , \ *cfgserver*\ , \ *roles*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Configuration management data for nodes used by non-xCAT osimage management services to install and configure software on a node.


******************
cfgmgt Attributes:
******************



\ **node**\ 
 
 The node being managed by the cfgmgr service
 


\ **cfgmgr**\ 
 
 The name of the configuration manager service.  Currently 'chef' and 'puppet' are supported services.
 


\ **cfgserver**\ 
 
 The xCAT node name of the chef server or puppet master
 


\ **roles**\ 
 
 The roles associated with this node as recognized by the cfgmgr for the software that is to be installed and configured.  These role names map to chef recipes or puppet manifest classes that should be used for this node.  For example, chef OpenStack cookbooks have roles such as mysql-master,keystone, glance, nova-controller, nova-conductor, cinder-all.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

