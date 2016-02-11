
##########
winstall.8
##########

.. highlight:: perl


****
Name
****


\ **winstall**\  - Begin OS provision on a noderange


****************
\ **Synopsis**\ 
****************


\ **winstall**\  [\ **-o | -**\ **-osver**\ ] [\ **-p | -**\ **-profile**\ ] [\ **-a | -**\ **-arch**\ ] [\ *noderange*\ ]

\ **winstall**\  [\ **-O | -**\ **-osimage**\ ] [\ *noderange*\ ]


*******************
\ **Description**\ 
*******************


\ **winstall**\  is a convenience tool that will change attributes as requested for operating system version, profile, and architecture, call \ **nodeset**\  to modify the network boot configuration, call \ **rsetboot**\  net to set the next boot over network (only support nodes
with "nodetype.mgt=ipmi", for other nodes, make sure the correct boot order has been set before \ **winstall**\ ), and \ **rpower**\  to begin a boot cycle.

If [\ **-O | -**\ **-osimage**\ ] is specified or nodetype.provmethod=\ *osimage*\  is set, provision the noderange with the osimage specified/configured, ignore the table change options if specified.

It  will then run wcons on the nodes.


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
 



****************
\ **Examples**\ 
****************



1. Provison nodes 1 through 20, using their current configuration.
 
 
 .. code-block:: perl
 
   winstall node1-node20
 
 


2. Provision nodes 1 through 20, forcing rhels5.1 and compute profile.
 
 
 .. code-block:: perl
 
   winstall node1-node20 -o rhels5.1 -p compute
 
 


3. Provision nodes 1 through 20 with the osimage rhels6.4-ppc64-netboot-compute.
 
 
 .. code-block:: perl
 
   winstall node1-node20 -O rhels6.4-ppc64-netboot-compute
 
 



************************
\ **See**\  \ **Also**\ 
************************


noderange(3)|noderange.3, rinstall(8)|rinstall.8, wcons(1)|wcons.1

