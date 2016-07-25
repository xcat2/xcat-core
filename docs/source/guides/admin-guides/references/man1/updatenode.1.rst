
############
updatenode.1
############

.. highlight:: perl


****
NAME
****


\ **updatenode**\  - Update nodes in an xCAT cluster environment.


********
SYNOPSIS
********


\ **updatenode**\  \ *noderange*\  [\ **-V | -**\ **-verbose**\ ] [\ **-F | -**\ **-sync**\ ] [\ **-f | -**\ **-snsync**\ ] [\ **-S | -**\ **-sw**\ ]  [\ **-l**\   \ *userID*\ ]  [\ **-P | -**\ **-scripts**\  [\ *script1,script2...*\ ]] [\ **-s | -**\ **-sn**\ ] [\ **-A | -**\ **-updateallsw**\ ] [\ **-c | -**\ **-cmdlineonly**\ ] [\ **-d**\  \ *alt_source_dir*\ ] [\ **-**\ **-fanout**\ =\ *fanout_value*\ ] [\ **-t**\  \ *timeout*\ } [\ *attr=val*\  [\ *attr=val...*\ ]] [\ **-n | -**\ **-noverify**\ ]

\ **updatenode**\  \ **noderange**\  [\ **-k | -**\ **-security**\ ] [\ **-t**\  \ *timeout*\ ]

\ **updatenode**\  \ **noderange**\  [\ **-g | -**\ **-genmypost**\ ]

\ **updatenode**\  \ **noderange**\  [\ **-V | -**\ **-verbose**\ ] [\ **-t**\  \ *timeout*\ ] [\ *script1,script2...*\ ]

\ **updatenode**\  \ **noderange**\  [\ **-V | -**\ **-verbose**\ ] [\ **-f | -**\ **-snsync**\ ]

\ **updatenode**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The updatenode command is run on the xCAT management node and can be used
to perform the following node updates:


1. Distribute and synchronize files.



2. Install or update software on diskful nodes.



3. Run postscripts.



4. Update the ssh keys and host keys for the service nodes and compute nodes;
Update the ca and credentials for the service nodes.



The default behavior when no options are input to updatenode will be to run  
the following options \ **-S**\ , \ **-P**\  and \ **-F**\  options in this order.
If you wish to limit updatenode to specific 
actions you can use combinations of the \ **-S**\ , \ **-P**\ , and \ **-F**\  flags.

For example, If you just want to synchronize configuration file you could
specify the \ **-F**\  flag.   If you want to synchronize files and update 
software you would specify the \ **-F**\  and \ **-S**\  flags. See the descriptions 
of these flags and examples below.

The flag \ **-k**\  (\ **-**\ **-security**\ ) can NOT be used together with \ **-S**\ , \ **-P**\ , and \ **-F**\  flags.

The flag \ **-f**\  (\ **-**\ **-snsync**\ ) can NOT be used together with \ **-S**\ , \ **-P**\ , and \ **-F**\  flags.

Note: In a large cluster environment the updating of nodes in an ad hoc 
manner can quickly get out of hand, leaving the system administrator with 
a very confusing environment to deal with. The updatenode command is 
designed to encourage users to handle cluster updates in a manner that 
is recorded and easily repeatable.

To distribute and synchronize files
===================================


The basic process for distributing and synchronizing nodes is:


\* Create a synclist file.



\* Indicate the location of the synclist file.



\* Run the updatenode command to update the nodes.



Files may be distributed and synchronized for both diskless and 
diskful nodes.  Syncing files to NFS-based statelite nodes is not supported.

More information on using the  synchronization file function is in the following doc: Using_Updatenode.

Create the synclist file
------------------------


The synclist file contains the configuration entries that specify 
where the files should be synced to. In the synclist file, each 
line is an entry which describes the location of the source files 
and the destination location for the files on the target node.

For more information on creating your synclist files and where to put them, read:

Sync-ing_Config_Files_to_Nodes


Run updatenode to synchronize the files
---------------------------------------



.. code-block:: perl

   updatenode <noderange> -F




To install or update software
=============================


updatenode can be use to install or update software on the nodes. See the following documentation for setting up otherpkgs:
Install_Additional_Packages

To install/update the packages, run:


.. code-block:: perl

   updatenode <noderange> -S


\ **For Linux systems:**\ 

It this is equivalent to running the 
following command:


.. code-block:: perl

  updatenode noderange -P ospkgs,otherpkgs


It will update all the rpms specified in the .pkglist file and .otherpkgs.pkglist 
file. ospkgs postscript will normally remove all the existing rpm 
repositories before adding server:/install/<os>/<arch/ as the new repository. 
To preserve the existing repositories, you can run the following command instead:


.. code-block:: perl

   updatenode noderange -P "ospkgs --keeprepo,otherpkgs"


\ **For AIX systems:**\ 

Note: The updatenode command is used to update AIX diskful nodes only. For updating diskless AIX nodes refer to the xCAT for AIX update documentation and use the xCAT mknimimage command.
For information on updating software on AIX cluster:
For diskful installs, read:
XCAT_AIX_RTE_Diskful_Nodes
For diskless installs, read:
XCAT_AIX_Diskless_Nodes

updatenode can also be used in Sysclone environment to push delta changes to target node. After capturing the delta changes from the golden client to management node, just run below command to push delta changes to target nodes.


.. code-block:: perl

   updatenode <targetnoderange> -S



To run postscripts
==================


The scripts must be copied to the /install/postscripts 
directory on the xCAT management node. (Make sure they are 
executable and world readable.)

To run scripts on a node you must either specify them on the 
command line or you must add them to the "postscripts" attribute 
for the node.

To set the postscripts attribute of the node (or group) 
definition you can use the xCAT chdef command. Set the value to 
be a comma separated list of the scripts that you want to be 
executed on the nodes. The order of the scripts in the list 
determines the order in which they will be run.  You can use the 
lsdef command to check the postscript order.

Scripts can  be run on both diskless and diskful nodes.

To run all the customization scripts that have been designated 
for the nodes, (in the "postscripts and postbootscripts" attributes), type:


.. code-block:: perl

   updatenode <noderange> -P


To run the "syslog" script for the nodes, type:


.. code-block:: perl

   updatenode <noderange> -P syslog


To run a list of scripts, type:


.. code-block:: perl

   updatenode <noderange> -P "script1 p1 p2,script2"


where p1 p2 are the parameters for script1.

The flag '-P' can be omitted when only scripts names  are
specified.

Note: script1,script2 may or may not be designated as scripts to 
automatically run on the node. However, if you want script1 and 
script2 to get invoked next time the nodes are deployed then make sure 
to add them to the "postscripts/postbootscripts" attribute in the database for the nodes.


Update security
===============


The basic functions of update security for nodes:


\* Setup the ssh keys for the target nodes. It enables the management
node and service nodes to ssh to the target nodes without password.



\* Redeliver the host keys to the target nodes.



\* Redeliver the ca and certificates files to the service node.
These files are used to authenticate the ssl connection between
xcatd's of management node and service node.



\* Remove the entries of target nodes from known_hosts file.



\ *Set up the SSH keys*\ 

A password for the user who is running this command is needed to setup
the ssh keys. This user must have the same uid and gid as
the userid on the target node where the keys will be setup.

If the current user is root, roots public ssh keys will be put in the
authorized_keys\* files under roots .ssh directory on the node(s).
If the current user is non-root, the user must be in the policy table
and have credential to run the xdsh command.
The non-root users public ssh keys and root's public ssh keys will be put in
the authorized_keys\* files under the non-root users .ssh directory on the node(s
).

\ *Handle the hierarchical scenario*\ 

When update security files for the node which is served by a service node,
the service node will be updated automatically first, and then the target
node.

The certificates files are needed for a service node to authenticate
the ssl connections between the xCAT client and xcatd on the service node,
and the xcatd's between service node and management node. The files in the
directories /etc/xcat/cert/ and ~/.xcat/ will be updated.

Since the certificates have the validity time, the ntp service is recommended 
to be set up between management node and service node.

Simply running following command to update the security keys:


.. code-block:: perl

  updatenode <noderange> -k




**********
PARAMETERS
**********



\ *noderange*\ 
 
 A set of comma delimited xCAT node names
 and/or group names. See the xCAT "noderange"
 man page for details on additional supported 
 formats.
 


\ *script1,script2...*\ 
 
 A comma-separated list of script names. 
 The scripts must be executable and copied 
 to the /install/postscripts directory.
 Each script can take zero or more parameters.
 If parameters are spcified, the whole list needs to be quoted by double quotes. 
 For example:
 
 
 .. code-block:: perl
 
   "script1 p1 p2,script2"
 
 


[\ *attr=val*\  [\ *attr=val...*\ ]]
 
 Specifies one or more "attribute equals value" pairs, separated by spaces.
 Attr=val pairs must be specified last on the command line.  The currently
 supported attributes are: "installp_bundle", "otherpkgs", "installp_flags", 
 "emgr_flags" and "rpm_flags".  These attribute are only valid for AIX software
 maintenance support.
 



*******
OPTIONS
*******



\ **-**\ **-fanout**\ =\ *fanout_value*\ 
 
 Specifies a fanout value for the maximum number of  concur-
 rently  executing  remote shell processes. Serial execution
 can be specified by indicating a fanout value of \ **1**\ .  If \ **-**\ **-fanout**\  is not specified, a default fanout value of \ **64**\  is used.
 


\ **-A|-**\ **-updateallsw**\ 
 
 Install or update all software contained in the source directory. (AIX only)
 


\ **-c|cmdlineonly**\ 
 
 Specifies that the updatenode command should only use software maintenance
 information provided on the command line.  This flag is only valid when
 using AIX software maintenance support.
 


\ **-d**\  \ *alt_source_dir*\ 
 
 Used to specify a source directory other than the standard lpp_source directory specified in the xCAT osimage definition.  (AIX only)
 


\ **-F|-**\ **-sync**\ 
 
 Specifies that file synchronization should be
 performed on the nodes.  rsync and ssh must
 be installed and configured on the nodes. 
 The function is not supported for NFS-based statelite installations.
 For NFS-based statelite installations to sync files, you should use the
 read-only option for files/directories listed in
 litefile table with source location specified in the litetree table.
 


\ **-f|-**\ **-snsync**\ 
 
 Specifies that file synchronization should be
 performed to the service nodes that service the
 nodes in the noderange. This updates the service
 nodes with the data to sync to the nodes. rsync and ssh must
 be installed and configured on the service nodes.
 For hierarchy, this optionally can  be done before syncing the files
 to the nodes with the -F flag.  If the -f flag is not used, then
 the -F flag will sync the servicenodes before the nodes automatically.
 When installing nodes in a hierarchical cluster, this flag should be
 used to sync the service nodes before the install, since the files will
 be sync'd from the service node by the syncfiles postscript during the
 install.
 The function is not supported for NFS-based statelite installations.
 For statelite installations to sync files, you should use the
 read-only option for files/directories listed in
 litefile table with source location specified in the litetree table.
 


\ **-g|-**\ **-genmypost**\ 
 
 Will generate a new mypostscript file for the
 nodes in the noderange, if site precreatemypostscripts is 1 or YES.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-k|-**\ **-security**\ 
 
 Update the ssh keys and host keys for the service nodes and compute nodes;
 Update the ca and credentials to the service nodes.  Never run this command to the Management Node, it will take down xcatd.
 You must be running updatenode as root to use the -k flag.
 


\ **-l | -**\ **-user**\  \ *user_ID*\ 
 
 Specifies a non-root user name to use for remote command execution. This option is only available when running postscripts (-P) for 
 AIX and Linux and updating software (-S) for Linux only. 
 The non-root userid  must be previously defined as an xCAT user. 
 The userid sudo setup will have to be done by the admin on the node.
 This is not supported in a hiearchical cluster, that is the node is serviced by a service node. 
 See the document Granting_Users_xCAT_privileges for required xcat/sudo setup.
 


\ **-P|-**\ **-scripts**\ 
 
 Specifies that postscripts and postbootscripts should be run on the nodes. 
 updatenode -P syncfiles is not supported.  The syncfiles postscript can only
 be run during install.  You should use updatenode <noderange> -F instead.
 


\ **-S|-**\ **-sw**\ 
 
 Specifies that node software should be updated.  In Sysclone environment, specifies pushing the delta changes to target nodes.
 


\ **-n|-**\ **-noverify**\ 
 
 Specifies that node network availability verification will be skipped.
 


\ **-s|-**\ **-sn**\ 
 
 Set the server information stored on the nodes in /opt/xcat/xcatinfo on Linux.
 


\ **-t**\  \ *timeout*\ 
 
 Specifies a timeout in seconds the command will wait for the remote targets to complete. If timeout is not specified
 it will wait indefinitely. updatenode -k is the exception that has a timeout of 10 seconds, unless overridden by this flag.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To perform all updatenode features for the Linux nodes in the group "compute":
 
 
 .. code-block:: perl
 
   updatenode compute
 
 
 The command will: run any scripts listed in the nodes "postscripts and postbootscripts" 
 attribute, install or update any software indicated in the 
 /install/custom/install/<ostype>/profile.otherpkgs.pkglist (refer to the 
 \ **To install or update software part**\ ), synchronize any files indicated by 
 the synclist files specified in the osimage "synclists" attribute.
 


2. To run postscripts,postbootscripts and file synchronization only on the node "clstrn01":
 
 
 .. code-block:: perl
 
   updatenode clstrn01 -F -P
 
 


3. Running updatenode -P with the syncfiles postscript is not supported. You should use updatenode -F instead.
 
 Do not run:
 
 
 .. code-block:: perl
 
   updatenode clstrno1 -P syncfiles
 
 
 Run:
 
 
 .. code-block:: perl
 
   updatenode clstrn01 -F
 
 


4. To run the postscripts and postbootscripts  indicated in the postscripts and postbootscripts attributes on the node "clstrn01":
 
 
 .. code-block:: perl
 
   updatenode clstrn01 -P
 
 


5. To run the postscripts script1 and script2 on the node "clstrn01":
 
 
 .. code-block:: perl
 
   cp script1,script2 /install/postscripts
  
   updatenode clstrn01 -P "script1 p1 p2,script2"
 
 
 Since flag '-P' can be omitted when only script names are specified, 
 the following command is equivalent:
 
 
 .. code-block:: perl
 
   updatenode clstrn01 "script1 p1 p2,script2"
 
 
 p1 p2 are parameters for script1.
 


6. To synchronize the files on the node "clstrn01":  Prepare the synclist file. 
For AIX, set the full path of synclist in the osimage table synclists 
attribute. For Linux, put the synclist file into the location: 
/install/custom/<inst_type>/<distro>/<profile>.<os>.<arch>.synclist
Then:
 
 
 .. code-block:: perl
 
   updatenode clstrn01 -F
 
 


7. To perform the software update on the Linux node "clstrn01":  Copy the extra 
rpm into the /install/post/otherpkgs/<os>/<arch>/\* and add the rpm names into 
the /install/custom/install/<ostype>/profile.otherpkgs.pkglist .  Then:
 
 
 .. code-block:: perl
 
   updatenode clstrn01 -S
 
 


8. To update the AIX node named "xcatn11" using the "installp_bundle" and/or
"otherpkgs" attribute values stored in the xCAT database.  Use the default installp, rpm and emgr flags.
 
 
 .. code-block:: perl
 
   updatenode xcatn11 -V -S
 
 
 Note: The xCAT "xcatn11" node definition points to an xCAT osimage definition 
 which contains the "installp_bundle" and "otherpkgs" attributes as well as
 the name of the NIM lpp_source resource.
 


9. To update the AIX node "xcatn11" by installing the "bos.cpr" fileset using 
the "-agQXY" installp flags.  Also display the output of the installp command.
 
 
 .. code-block:: perl
 
   updatenode xcatn11 -V -S otherpkgs="I:bos.cpr" installp_flags="-agQXY"
 
 
 Note:  The 'I:' prefix is optional but recommended for installp packages.
 


10. To uninstall the "bos.cpr" fileset that was installed in the previous example.
 
 
 .. code-block:: perl
 
   updatenode xcatn11 -V -S otherpkgs="I:bos.cpr" installp_flags="-u"
 
 


11. To update the AIX nodes "xcatn11" and "xcatn12" with the "gpfs.base" fileset
and the "rsync" rpm using the installp flags "-agQXY" and the rpm flags "-i --nodeps".
 
 
 .. code-block:: perl
 
   updatenode xcatn11,xcatn12 -V -S otherpkgs="I:gpfs.base,R:rsync-2.6.2-1.aix5.1.ppc.rpm" installp_flags="-agQXY" rpm_flags="-i --nodeps"
 
 
 Note: Using the "-V" flag with multiple nodes may result in a large amount of output.
 


12. To uninstall the rsync rpm that was installed in the previous example.
 
 
 .. code-block:: perl
 
   updatenode xcatn11 -V -S otherpkgs="R:rsync-2.6.2-1" rpm_flags="-e"
 
 


13. Update the AIX node "node01" using the software specified in the NIM "sslbnd" and "sshbnd" installp_bundle resources and the "-agQXY" installp flags.
 
 
 .. code-block:: perl
 
   updatenode node01 -V -S installp_bundle="sslbnd,sshbnd" installp_flags="-agQXY"
 
 


14. To get a preview of what would happen if you tried to install the "rsct.base" fileset on AIX node "node42".  (You must use the "-V" option to get the full output from the installp command.)
 
 
 .. code-block:: perl
 
   updatenode node42 -V -S otherpkgs="I:rsct.base" installp_flags="-apXY"
 
 


15. To check what rpm packages are installed on the AIX node "node09". (You must use the "-c" flag so updatenode does not get a list of packages from the database.)
 
 
 .. code-block:: perl
 
   updatenode node09 -V -c -S rpm_flags="-qa"
 
 


16. To install all software updates contained in the /images directory.
 
 
 .. code-block:: perl
 
   updatenode node27 -V -S -A -d /images
 
 
 Note:  Make sure the directory is exportable and that the permissions are set
 correctly for all the files.  (Including the .toc file in the case of
 installp filesets.)
 


17. Install the interim fix package located in the /efixes directory.
 
 
 .. code-block:: perl
 
   updatenode node29 -V -S -d /efixes otherpkgs=E:IZ38930TL0.120304.epkg.Z
 
 


18. To uninstall the interim fix that was installed in the previous example.
 
 
 .. code-block:: perl
 
   updatenode xcatsn11 -V -S -c emgr_flags="-r -L IZ38930TL0"
 
 


19. To update the security keys for the node "node01"
 
 
 .. code-block:: perl
 
   updatenode node01 -k
 
 


20. To update the service nodes with the files to be synchronized to node group compute:
 
 
 .. code-block:: perl
 
   updatenode compute -f
 
 


21. To run updatenode with the non-root userid "user1" that has been setup as an xCAT userid  with sudo on node1  to run as root, do the following:
See  Granting_Users_xCAT_privileges for required sudo setup.
 
 
 .. code-block:: perl
 
   updatenode node1 -l user1 -P syslog
 
 


22. In Sysclone environment, after capturing the delta changes from golden client to management node, to run updatenode to push these delta changes to target nodes.
 
 
 .. code-block:: perl
 
   updatenode target-node -S
 
 



*****
FILES
*****


/opt/xcat/bin/updatenode

