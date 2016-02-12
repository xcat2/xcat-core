
########
rmzone.1
########

.. highlight:: perl


************
\ **NAME**\ 
************


\ **rmzone**\  - Removes a zone from the cluster.


****************
\ **SYNOPSIS**\ 
****************


\ **rmzone**\  \ *zonename*\   [\ **-g**\ ] [\ **-f**\ ]

\ **rmzone**\  [\ **-h**\  | \ **-v**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **rmzone**\  command is designed to remove a previously defined zone from the cluster.
It will remove the zone entry in the zone table.  It will remove the zone from the zonename attributes on the nodes that were assigned to the zone. Optionally, it will remove the zonename group from the nodes that were assigned to the zone. 
It will also remove the root ssh keys that were created for that zone on the Management Node. 
The rmzone command is only supported on Linux ( No AIX support).
The nodes are not automatically updated with new root ssh keys by rmzone.  You must run updatenode -k  or xdsh -K to the nodes to update the root ssh keys. The nodes new ssh key will be assigned from the defaultzone in the zone table, or if  no entries in the zone table,  the keys will come from /root/.ssh.   
Note: if any zones in the zone table, there must be one and only one defaultzone. Otherwise, errors will occur.


***************
\ **OPTIONS**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-v | -**\ **-version**\ 
 
 Displays command version and build date.
 


\ **-f | -**\ **-force**\ 
 
 Used to remove a zone that is defined as current default zone.  This should only be done if you are removing all zones, or you will
 adding a new zone or changing an existing zone to be the default zone.
 


\ **-g | -**\ **-assigngroup**\ 
 
 Remove the assigned group named \ **zonename**\  from all nodes assigned to the zone being removed.
 


\ **-V | -**\ **-Verbose**\ 
 
 Verbose mode.
 



****************
\ **Examples**\ 
****************



1. To remove zone1 from the zone table and the zonename attribute on all it's assigned nodes , enter:
 
 
 .. code-block:: perl
 
   rmzone zone1
 
 


2.
 
 To remove zone2 from the zone table, the zone2 zonename attribute, and the zone2 group assigned to all nodes that were in zone2, enter:
 
 
 .. code-block:: perl
 
   rmzone zone2 -g
 
 


3.
 
 To remove zone3 from the zone table, all the node zone attributes and  override the fact it is the defaultzone,  enter:
 
 
 .. code-block:: perl
 
   rmzone zone3 -g -f
 
 


\ **Files**\ 

\ **/opt/xcat/bin/rmzone/**\ 

Location of the rmzone command.


****************
\ **SEE ALSO**\ 
****************


L <mkzone(1)|mkzone.1>,L <chzone(1)|chzone.1>,L <xdsh(1)|xdsh.1>, updatenode(1)|updatenode.1

