
########
mkzone.1
########

.. highlight:: perl


************
\ **NAME**\ 
************


\ **mkzone**\  - Defines a new zone in the cluster.


****************
\ **SYNOPSIS**\ 
****************


\ **mkzone**\  \ *zonename*\   [\ **-**\ **-defaultzone**\ ] [\ **-k**\  \ *full path to the ssh RSA private key*\ ] [\ **-a**\  \ *noderange*\ ] [\ **-g**\ ] [\ **-f**\ ] [\ **-s**\  \ *{yes|no}*\ ] [\ **-V**\ ]

\ **mkzone**\  [\ **-h**\  | \ **-v**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **mkzone**\  command is designed to divide the xCAT cluster into multiple zones. The nodes in each zone will share common root ssh keys. This allows the nodes in a zone to be able to as root ssh to each other without password, but cannot do the same to any node in another zone. All zones share a common xCAT Management Node and database including the site table, which defines the attributes of the entire cluster.
The mkzone command is only supported on Linux ( No AIX support).
The nodes are not updated with the new root ssh keys by mkzone.  You must run updatenode -k  or xdsh -K to the nodes to update the root ssh keys to the new generated zone keys. This will also sync any service nodes with the zone keys, if you have a hierarchical cluster.   
Note: if any zones in the zone table, there must be one and only one defaultzone. Otherwise, errors will occur.


***************
\ **OPTIONS**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-v | -**\ **-version**\ 
 
 Displays command version and build date.
 


\ **-k | -**\ **-sshkeypath**\  \ *full path to the ssh RSA private key*\ 
 
 This is the path to the id_rsa key that will be used to build root's ssh keys for the zone. If -k is used, it will generate the ssh public key from the input ssh RSA private key and store both in /etc/xcat/sshkeys/<zonename>/.ssh directory.
 If -f is not used,  then it will generate a set of root ssh keys for the zone and store them in /etc/xcat/sshkeys/<zonename>/.ssh.
 


\ **-**\ **-default**\ 
 
 if --defaultzone is input, then it will set the zone defaultzone attribute to yes; otherwise it will set to no.
 if --defaultzone is input and another zone is currently the default,
 then the -f flag must be used to force a change to the new defaultzone.
 If -f flag is not use an error will be returned and no change made. 
 Note: if any zones in the zone table, there must be one and only one defaultzone. Otherwise, errors will occur.
 


\ **-a | -**\ **-addnoderange**\  \ *noderange*\ 
 
 For each node in the noderange, it will set the zonename attribute for that node to the input zonename.
 If the -g flag is also on the command, then
 it will add the group name "zonename" to each node in the noderange.
 


\ **-s| -**\ **-sshbetweennodes**\  \ **yes|no**\ 
 
 If -s entered, the zone sshbetweennodes attribute will be set to yes or no. It defaults to yes. When this is set to yes, then ssh will be setup
 to allow passwordless root access between nodes.  If no, then root will be prompted for a password when running ssh between the nodes in the zone.
 


\ **-f | -**\ **-force**\ 
 
 Used with the (--defaultzone) flag to override the current default zone.
 


\ **-g | -**\ **-assigngroup**\ 
 
 Used with the (-a) flag to create the group zonename for all nodes in the input noderange.
 


\ **-V | -**\ **-Verbose**\ 
 
 Verbose mode.
 



****************
\ **EXAMPLES**\ 
****************



1. To make a new zone1 using defaults, enter:
 
 
 .. code-block:: perl
 
   mkzone zone1
 
 
 Note: with the first \ **mkzone**\ , you will automatically get the xcatdefault zone created as the default zone.  This zone uses ssh keys from <roothome>/.ssh directory.
 


2. To make a new zone2 using defaults and make it the default zone enter:
 
 
 .. code-block:: perl
 
   mkzone> zone2 --defaultzone -f
 
 


3.
 
 To make a new zone2A using the ssh id_rsa private key in /root/.ssh:
 
 
 .. code-block:: perl
 
   mkzone zone2A -k /root/.ssh
 
 


4.
 
 To make a new zone3 and assign the noderange compute3 to the zone  enter:
 
 
 .. code-block:: perl
 
   mkzone zone3 -a compute3
 
 


5. To make a new zone4 and assign the noderange compute4 to the zone and add zone4 as a group to each node  enter:
 
 
 .. code-block:: perl
 
   mkzone zone4 -a compute4 -g
 
 


6.
 
 To make a new zone5 and assign the noderange compute5 to the zone and add zone5 as a group to each node but not allow passwordless ssh between the nodes  enter:
 
 
 .. code-block:: perl
 
   mkzone zone5 -a compute5 -g -s no
 
 



*************
\ **Files**\ 
*************


/opt/xcat/bin/mkzone/

Location of the mkzone command.


****************
\ **SEE ALSO**\ 
****************


chzone(1)|chzone.1, rmzone(1)|rmzone.1, xdsh(1)|xdsh.1, updatenode(1)|updatenode.1

