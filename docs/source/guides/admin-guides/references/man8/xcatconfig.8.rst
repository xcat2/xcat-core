
############
xcatconfig.8
############

.. highlight:: perl


****
NAME
****


\ **xcatconfig**\  - Sets up the  Management Node during the xCAT install.


********
SYNOPSIS
********


\ **xcatconfig**\  [\ **-h | -**\ **-help**\ ]

\ **xcatconfig**\  [\ **-v | -**\ **-version**\ ]

\ **xcatconfig**\  [\ **-i | -**\ **-initinstall**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **xcatconfig**\  [\ **-u | -**\ **-updateinstall**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **xcatconfig**\  [\ **-k | -**\ **-sshkeys**\ ] [\ **-s | -**\ **-sshnodehostkeys**\ ] [\ **-c | -**\ **-credentials**\ ] [\ **-d | -**\ **-database**\ ] [\ **-m | -**\ **-mgtnode**\ ] [\ **-t | -**\ **-tunables**\ ] [\ **-V | -**\ **-verbose**\ ]

\ **xcatconfig**\  [\ **-f | -**\ **-force**\ ] [\ **-V | -**\ **-verbose**\ ]


***********
DESCRIPTION
***********


\ **xcatconfig**\  Performs basic xCAT setup operations on an xCAT management node. This command should not be run on an xCAT Service Node, unless you are making it a Management Node. See flag description below for more details.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Displays the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Displays the release version of the code.
 


\ **-V|-**\ **-verbose**\ 
 
 Displays verbose messages.
 


\ **-i|-**\ **-initialinstall**\ 
 
 The install option is normally run as a post operation from the rpm xCAT.spec file during the initial install of xCAT on the Management Node. It will setup the root ssh keys, ssh node keys, xCAT credentials, initialize the datebase, export directories, start syslog and other daemons as needed after the initial install of xCAT.
 


\ **-u|-**\ **-updateinstall**\ 
 
 The update install option is normally run as a post operation from the rpm xCAT.spec file during an update install of xCAT on the Management Node. It will check the setup the root ssh keys, ssh node keys, xCAT credentials, datebase, exported directories, syslog and the state of daemons needed by xCAT, after the updateinstall of xCAT. If setup is required, it will perform the operation.  It will restart the necessary daemons.
 


\ **-k|-**\ **-sshkeys**\ 
 
 This option will remove and regenerate the root id_rsa keys.  It should only be used, if the keys are  deleted or corrupted. The keys must then be distribute to the nodes by installing, running updatenode -k, or using xdsh -K option, for root to be able to ssh to the nodes without being prompted for a password. 
 rspconfig will need to be run to distribute the key to the MM and HMCs. Any device, we need to ssh from the MN to the device will also have to be updated with the new ssh keys.
 


\ **-s|-**\ **-sshnodehostkeys**\ 
 
 This option will remove and regenerate the node host ssh keys.  It should only be used, if the keys are deleted or are corrupted. The keys must then be redistribute to the nodes by installing, running updatenode -k  or using xdcp or pcp to copy the keys from /etc/xcat/hostkeys directory to the /etc/ssh directory on the nodes.
 


\ **-c|-**\ **-credentials**\ 
 
 This option will remove all xcat credentials for root and any userids where credentials have been created. It will regenerate roots credentials,  but the admin will have to add back all the userid credentials needed with the /opt/xcat/share/xcat/scripts/setup-local-client.sh <username> command.  It should only be used, if they are deleted or become corrupted. The root credentials must be redistribed to the service nodes by installing the service node or using updatenode -k.  makeconservercf must be rerun to pick up the new credentials,  and conserver must be stop and started.
 


\ **-d|-**\ **-database**\ 
 
 This option will reinitialize the basic xCAT database table setup.  It will not remove any new database entries that have been added, but it is strongly suggested that you backup you database (dumpxCATdb) before using it.
 


\ **-f|-**\ **-force**\ 
 
 The force option may  be used after the install to reinitialize the Management Node. This option will  regenerate keys, credential and reinititialize the site table. This option should be used, if keys or credentials become corrupt or lost. 
 Additional action must be taken after using the force options.  ssh keys must be redistributed to the nodes, site table attributes might need to be restored, makeconservercf needs to be rerun to pick up the new credentials and conserver stopped and started, rspconfig needs to be rerun to distribute the new keys to the MM and the HMCs. 
 A new set of common ssh host keys will have  been generated for the nodes. If you wish your nodes to be able to ssh to each other with out password intervention,  then you should redistribute these new keys to the nodes. If the nodes hostkeys are updated then you will need to remove their entries from the known_hosts files on the management node before using ssh, xdsh, xdcp. 
 Redistribute credentials and ssh keys to the service nodes and ssh keys to the nodes by using the updatenode -k command.
 


\ **-m|-**\ **-mgtnode**\ 
 
 This option will add the Management Node to the database with the correct attributes set to be recognized by xCAT.  This should be run after the hostname of the Management Node is set to the name that  will resolve to the cluster-facing NIC.
 


\ **-t|-**\ **-tunables**\ 
 
 This option will set tunable parameters on the Management and Service nodes recommended for your Linux cluster.  It will only set them during initial install, if you run xcatconfig -f or xcatconfig -t.
 



********
EXAMPLES
********



1. To force regeneration of keys and credentials and reinitialize the site table:
 
 
 .. code-block:: perl
 
   xcatconfig -f
 
 


2. To regenerate root's ssh keys:
 
 
 .. code-block:: perl
 
   xcatconfig -k
 
 


3. To regenerate node host ssh keys:
 
 
 .. code-block:: perl
 
   xcatconfig -s
 
 


4. To regenerate node host ssh keys and credentials:
 
 
 .. code-block:: perl
 
   xcatconfig -s -c
 
 


5. To add the Management Node to the DB:
 
 
 .. code-block:: perl
 
   xcatconfig -m
 
 


