
##########
rinstall.8
##########

.. highlight:: perl


****
Name
****


\ **rinstall**\  - Begin OS provision on a noderange


****************
\ **Synopsis**\ 
****************


\ **rinstall**\  [\ *-o*\ |\ *-**\ **-osver*\ ] [\ *-p*\ |\ *-**\ **-profile*\ ] [\ *-a*\ |\ *-**\ **-arch*\ ] [\ *-c*\ |\ *-**\ **-console*\ ] [\ *noderange*\ ]

\ **rinstall**\  [\ *-O*\ |\ *-**\ **-osimage*\ ] [\ *-c*\ |\ *-**\ **-console*\ ] [\ *noderange*\ ]


*******************
\ **Description**\ 
*******************


\ **rinstall**\  is a convenience command that will change tables as requested for operating system version, profile, and architecture, call \ **nodeset**\  to modify the network boot configuration, call \ **rsetboot**\  net to set the next boot over network (only support nodes with "nodetype.mgt=ipmi", for other nodes, make sure the correct boot order has been set before \ **rinstall**\ ), and \ **rpower**\  to begin a boot cycle.

If [\ *-O*\ |\ *--osimage*\ ] is specified or nodetype.provmethod=\ *osimage*\  is set, provision the noderange with the osimage specified/configured, ignore the table change options if specified.

If -c is specified, it will then run rcons on the node. This is allowed only if one node in the noderange.   If need consoles on multiple nodes , see winstall(8)|winstall.8.


***************
\ **Options**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Display usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display version.
 


\ **-o | -**\ **-osver**\ 
 
 Specifies which os version to provision.  If unspecified, the current node os setting is used. Will be ignored if [\ *-O*\ |\ *--osimage*\ ] is specified or nodetype.provmethod=\ *osimage*\ .
 


\ **-p | -**\ **-profile**\ 
 
 Specifies what profile should be used of the operating system.  If not specified the current node profile setting is used. Will be ignored if [\ *-O*\ |\ *--osimage*\ ] is specified or nodetype.provmethod=\ *osimage*\ .
 


\ **-a | -**\ **-arch**\ 
 
 Specifies what architecture of the OS to provision.  Typically this is unneeded, but if provisioning between x86_64 and x86 frequently, this may be a useful flag. Will be ignored if [\ *-O*\ |\ *--osimage*\ ] is specified or nodetype.provmethod=\ *osimage*\ .
 


\ **-O | -**\ **-osimage**\ 
 
 Specifies the osimage to provision.
 


\ **-c | -**\ **-console**\ 
 
 Requests that rinstall runs rcons once the provision starts.  This will only work if there is only one node in the noderange. See winstall(8)|winstall.8 for starting nsoles on multiple nodes.
 



****************
\ **Examples**\ 
****************


\ **rinstall**\  \ *node1-node20*\ 

Provison nodes 1 through 20, using their current configuration.

\ **rinstall**\  \ *node1-node20*\  -o rhels5.1 -p compute

Provision nodes 1 through 20, forcing rhels5.1 and compute profile.

\ **rinstall**\  \ *node1-node20*\  -O rhels6.4-ppc64-netboot-compute

Provision nodes 1 through 20 with the osimage rhels6.4-ppc64-netboot-compute.

\ **rinstall**\   \ *node1*\  -c

Provisoon node1 and start a console to monitor the process.


************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, winstall(8)|winstall.8, rcons(1)|rcons.1

