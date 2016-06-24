
########
chzone.1
########

.. highlight:: perl


************
\ **NAME**\ 
************


\ **chzone**\  - Changes a zone defined  in the cluster.


****************
\ **SYNOPSIS**\ 
****************


\ **chzone**\  \ *zonename*\   [\ **-**\ **-defaultzone**\ ] \ **[-K]**\  [\ **-k**\  \ *full path to the ssh RSA private key*\ ] [\ **-a**\  \ *noderange*\  | \ **-r**\  \ *noderange*\ ] [\ **-g**\ ] [\ **-f**\ ] [\ **-s**\  \ **{yes|no}**\ ] [\ **-V**\ ]

\ **chzone**\  [\ **-h**\  | \ **-v**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **chzone**\  command is designed to change the definition of a zone previous defined in the cluster.
The chzone command is only supported on Linux ( No AIX support).
The nodes are not updated with the new root ssh keys by chzone. You must run updatenode -k  or xdsh -K to the nodes to update the root ssh keys to the new generated zone keys. This will also sync any service nodes with the zone keys, if you have a hierarchical cluster.   
Note: if any zones in the zone table, there must be one and only one defaultzone. Otherwise, errors will occur.


***************
\ **OPTIONS**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-v | -**\ **-version**\ 
 
 Displays command version and build date.
 


\ **-k | -**\ **-sshkeypath**\  \ *full path to the ssh RSA private key*\ 
 
 This is the path to the id_rsa key that will be used to build new root's ssh keys for the zone. If -k is used, it will generate the ssh public key from the input ssh RSA private key, and store both in /etc/xcat/sshkeys/<zonename>/.ssh directory.
 


\ **-K | -**\ **-genkeys**\ 
 
 Using this flag, will  generate new ssh RSA private and public keys for the zone into the /etc/xcat/sshkeys/<zonename>/.ssh directory.
 The nodes are not automatically updated with the new root ssh keys by chzone. You must run updatenode -k  or xdsh -K to the nodes to update the root ssh keys to the new generated zone keys. This will also sync any service nodes with the zone keys, if you have a hierarchical cluster.
 


\ **-**\ **-defaultzone**\ 
 
 if \ **-**\ **-defaultzone**\  is input, then it will set the zone defaultzone attribute to yes.
 if \ **-**\ **-defaultzone**\  is input and another zone is currently the default,
 then the \ **-f**\  flag must be used to force a change to the new defaultzone.
 If \ **-f**\  flag is not use an error will be returned and no change made. 
 Note: if any zones in the zone table, there must be one and only one defaultzone. Otherwise, errors will occur.
 


\ **-a | -**\ **-addnoderange**\  \ *noderange*\ 
 
 For each node in the noderange, it will set the zonename attribute for that node to the input zonename.
 If the -g flag is also on the command, then
 it will add the group name "zonename" to each node in the noderange.
 


\ **-r | -**\ **-rmnoderange**\  \ *noderange*\ 
 
 For each node in the noderange, if the node is a member of the input zone, it will remove the zonename attribute for that node.
 If any of the nodes in the noderange is not a member of the zone, you will get an error and nothing will be changed.
 If the -g flag is also on the command, then
 it will remove the group name "zonename" from each node in the noderange.
 


\ **-s| -**\ **-sshbetweennodes**\  \ **yes|no**\ 
 
 If -s entered, the zone sshbetweennodes attribute will be set to yes or no based on the input. When this is set to yes, then ssh will be setup to allow passwordless root access between nodes.  If no, then root will be prompted for a password when running ssh between the nodes in the zone.
 


\ **-f | -**\ **-force**\ 
 
 Used with the \ **-**\ **-defaultzone**\  flag to override the current default zone.
 


\ **-g | -**\ **-assigngroup**\ 
 
 Used with the \ **-a**\  or \ **-r**\  flag to add or remove the group zonename for all nodes in the input noderange.
 


\ **-V | -**\ **-Verbose**\ 
 
 Verbose mode.
 



****************
\ **EXAMPLES**\ 
****************



1. To chzone zone1 to the default zone, enter:
 
 
 .. code-block:: perl
 
   chzone> zone1 --default -f
 
 


2. To generate new root ssh keys for zone2A using the ssh id_rsa private key in /root/.ssh:
 
 
 .. code-block:: perl
 
   chzone zone2A -k /root/.ssh
 
 
 Note: you must use xdsh -K or updatenode -k to update the nodes with the new keys
 


3. To generate new root ssh keys for zone2A, enter :
 
 
 .. code-block:: perl
 
   chzone zone2A -K
 
 
 Note: you must use xdsh -K or updatenode -k to update the nodes with the new keys
 


4. To add a new group of nodes (compute3) to zone3 and add zone3 group to the nodes,  enter:
 
 
 .. code-block:: perl
 
   chzone zone3 -a compute3 -g
 
 


5.
 
 To remove a group of nodes (compute4) from zone4 and remove zone4 group from the nodes,  enter:
 
 
 .. code-block:: perl
 
   chzone> zone4 -r compute4 -g
 
 


6. To change the sshbetweennodes setting on the zone to not allow passwordless ssh between nodes,  enter:
 
 
 .. code-block:: perl
 
   chzone zone5 -s no
 
 
 Note: you must use \ **xdsh -K**\  or \ **updatenode -k**\  to update the nodes with this new setting.
 



*************
\ **FILES**\ 
*************


/opt/xcat/bin/chzone/

Location of the chzone command.


****************
\ **SEE ALSO**\ 
****************


L <mkzone(1)|mkzone.1>,L <rmzone(1)|rmzone.1>,L <xdsh(1)|xdsh.1>, updatenode(1)|updatenode.1

