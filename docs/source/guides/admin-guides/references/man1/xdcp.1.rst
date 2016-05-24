
######
xdcp.1
######

.. highlight:: perl


************
\ **NAME**\ 
************


\ **xdcp**\  - Concurrently copies files to or from multiple nodes. In addition, provides an option to use rsync to update the files on the nodes, or to an installation image on the local node.


****************
\ **SYNOPSIS**\ 
****************


\ **xdcp**\  \ *noderange*\   [[\ **-B**\  | \ **-**\ **-bypass**\ ] [\ **-f**\  \ *fanout*\ ] [\ **-L**\ ]  [\ **-l**\   \ *userID*\ ] [\ **-o**\  \ *node_options*\ ] [\ **-p**\ ] [\ **-P**\ ] [\ **-r**\  \ *node_remote_shell*\ ] [\ **-R**\ ] [\ **-t**\  \ *timeout*\ ] [\ **-T**\ ] [\ **-v**\ ] [\ **-q**\ ] [\ **-X**\  \ *env_list*\ ] \ *sourcefile.... targetpath*\ 

\ **xdcp**\  \ *noderange*\   [\ **-F**\  \ *rsync input file*\ ]

\ **xdcp**\  \ *computenoderange*\   [\ **-s**\  \ **-F**\  \ *rsync input file*\ ]

\ **xdcp**\  [\ **-i**\  \ *path to install image*\ ] [\ **-F**\  \ *rsync input file*\ ]

\ **xdcp**\  [\ **-h**\  | \ **-V**\  | \ **-q**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **xdcp**\  command concurrently copies files  to  or  from  remote  target
nodes. The command issues a remote copy command for each node or device specified. When files are  pulled  from a target,  they  are  placed  into  the  target_path with the name of the
remote node or device appended to  the  copied  source_file  name.  The
/usr/bin/rcp command is the model for syntax and security. 
If using hierarchy, then xdcp runs on the service node that is servicing the compute node. The file will first be copied to the path defined in the site table, SNsyncfiledir attribute, or the default path /var/xcat/syncfiles on the service node, if the attribute is not defined. The -P flag will not automatically copy
the files from the compute node to the Management node, hierarchically.  There
is a two step process, see \ **-P**\  flag.  
If the Management Node is target node, it must be defined in the xCAT database with nodetype=mn. When the \ **xdcp**\  command runs the Management Node as the target, it does not use remote commands but uses the local OS copy (\ **cp**\ ) command.

\ **REMOTE**\  \ **USER**\ :

A  user_ID  can  be specified for the remote copy command.  Remote user
specification is identical for the xdcp and xdsh commands.  See  the  xdsh
command for more information.

\ **REMOTE**\  \ **COMMAND**\  \ **COPY**\ :

The  \ **xdcp**\   command  uses  a  configurable remote copy command to execute
remote copies on remote targets. Support is explicitly  provided  for
Remote  Shell  rcp  command,  the  OpenSSH  scp  command  and  the
/usr/bin/rsync command.

For node targets, the remote copy command is determined by the  follow-
ing order of precedence:

1. The \ **-r**\  flag.

2. The \ **/usr/bin/scp**\  command.

\ **COMMAND**\  \ **EXECUTIONS**\ :

The  maximum  number  of  concurrent remote copy command processes (the
fanout) can be specified with the \ **-f**\  flag or the DSH_FANOUT environment
variable.  The  fanout is only restricted by the number of remote shell
commands that can be run in  parallel.  You  can  experiment  with  the
DSH_FANOUT  value on your management server to see if higher values are
appropriate.

A timeout value for remote copy command execution can be specified with
the \ **-t**\  flag or DSH_TIMEOUT environment variable. If any remote target
does not respond within the timeout value, the xdcp command displays  an
error message and exits.

The \ **-T**\  flag provides diagnostic trace information for dcp command execution. Default settings and the actual remote copy commands that are executed to the remote targets are displayed.

The \ **xdcp**\  command can be executed silently using the \ **-Q**\  flag; no target
standard output or standard error is displayed.


***************
\ **OPTIONS**\ 
***************



\ *sourcefile...*\ 
 
 Specifies the complete path for the file to be  copied  to  or
 from  the  target.  Multiple files can be specified. When used
 with the -R flag, only a single directory  can  be  specified.
 When  used  with the -P flag, only a single file can be specified.
 


\ *targetpath*\ 
 
 If one source_file file, then it specifies the file to copy the source_file
 file to on the target. If multiple source_file files, it specifies
 the directory to copy the source_file files to on the target.
 If the -P flag is specified, the target_path is the local host location
 for the copied files.  The remote file directory structure is recreated
 under target_path and  the  remote  target  name  is  appended 
 to  the   copied source_file name in the target_path directory.
 Note: the targetpath directory must exist.
 


\ **-B | -**\ **-bypass**\ 
 
 Runs in bypass mode, use if the xcatd daemon is hung.
 


\ **-f | -**\ **-fanout**\  \ *fanout_value*\ 
 
 Specifies a fanout value for the maximum number of  concur-
 rently  executing  remote shell processes. Serial execution
 can be specified by indicating a fanout value of \ **1**\ .  
 If \ **-f**\  is not specified, a default fanout value of \ **64**\  is used.
 


\ **-F | -**\ **-File**\  \ *rsync input file*\ 
 
 Specifies the path to the file that will be used to  
 build the \ **rsync**\  command.
 The format of the input file is as follows, each line contains:
 
 
 .. code-block:: perl
 
   <path to source file1> <path to source file2> ... ->  < path to destination file/directory>
 
 
 or
 
 
 .. code-block:: perl
 
   <path to source file> -> <path to destination file>
 
 
 or
 
 
 .. code-block:: perl
 
   <path to source file> -> <path to destination directory ( must end in /)>
 
 
 For example:
 
 
 .. code-block:: perl
 
    /etc/password /etc/hosts -> /etc
  
    /tmp/file2  ->  /tmp/file2
  
    /tmp/file2  ->  /tmp/
  
    /tmp/filex  ->  /tmp/source/filey
  
    /etc/*  ->  /etc/
 
 
 \ **Running postscripts after files are sync'd to the nodes**\ :
 
 After you define the files to rsync, you can add an \ **EXECUTE:**\  clause in the synclist file. The \ **EXECUTE:**\  clause will list all the postscripts that you would like to run after the files are sync'd to the node. 
 The postscript file must be of the form \ **filename.post**\ , where the <filename>
 is the <filename> is the from <filename>, reside in the same
 directory as \ **filename**\ , and be executable.
 If the file \ **filename**\  is rsync'd to the node, then the \ **filename.post**\ 
 will automatically be run on the node.
 If the file \ **filename**\  is not updated on the node,  the \ **filename.post**\  will not be run.
 
 Putting the \ **filename.post**\  in the file list to rsync to the node is required
 for hierarchical clusters.  It is optional for non-hierarchical clusters.
 
 Another option is the \ **EXECUTEALWAYS:**\  clause in the synclist file.  The \ **EXECUTEALWAYS:**\  will list all the postscripts that you would like to run after the files are sync'd to the nodes.   These scripts will run whether or not any files are sync'd to the nodes.  The scripts have no special format, but must contain the fully qualified path.
 
 The scripts must be also added to the file list to rsync to the node for hierarchical clusters.  It is optional for non-hierarchical clusters.
 
 For example, your rsynclist file may look like this:
 
 
 .. code-block:: perl
 
   /tmp/share/file2  ->  /tmp/file2
   /tmp/share/file2.post -> /tmp/file2.post
   /tmp/share/file3  ->  /tmp/filex
   /tmp/share/file3.post -> /tmp/file3.post
   /tmp/myscript -> /tmp/myscript
   # the below are postscripts
   EXECUTE:
   /tmp/share/file2.post
   /tmp/share/file3.post
   EXECUTEALWAYS:
   /tmp/myscript
 
 
 If /tmp/file2 and /tmp/file3  update /tmp/file2 and /tmp/filex on the node, then the postscripts /tmp/file2.post and /tmp/file3.post are automatically run on 
 the node. /tmp/myscript will always be run on the node.
 
 Another option is the \ **APPEND:**\  clause in the synclist file. The \ **APPEND:**\  clause is used to append the contents of the input file to an existing file on the node.  The file to append \ **must**\  already exist on the node and not be part of the synclist that contains the \ **APPEND:**\  clause.
 
 For example, your rsynclist file may look like this:
 
 
 .. code-block:: perl
 
   /tmp/share/file2  ->  /tmp/file2
   /tmp/share/file2.post -> /tmp/file2.post
   /tmp/share/file3  ->  /tmp/filex
   /tmp/share/file3.post -> /tmp/file3.post
   /tmp/myscript -> /tmp/myscript
   # the below are postscripts
   EXECUTE:
   /tmp/share/file2.post
   /tmp/share/file3.post
   EXECUTEALWAYS:
   /tmp/myscript
   APPEND:
   /etc/myappenddir/appendfile -> /etc/mysetup/setup
   /etc/myappenddir/appendfile2 -> /etc/mysetup/setup2
 
 
 When you use the append script,  the file  (left) of the arrow is appended to the file right of the arrow.  In this example, /etc/myappenddir/appendfile is appended to /etc/mysetup/setup file, which must already exist on the node. The /opt/xcat/share/xcat/scripts/xdcpappend.sh is used to accomplish this.
 
 Another option is the \ **MERGE:**\  clause in the synclist file. The \ **MERGE:**\  clause is used to append the contents of the input file to /etc/passwd, /etc/group, or /etc/shadow on a Linux node.  It is only supported for those files and only on Linux. You must not use both the APPEND and MERGE funcion for these three files. The processing could end up not creating the file you desire. The MERGE function is the preferred method, becuase APPEND only adds to the file.  MERGE will add to the file but also insure there are no duplicate entries.
 
 For example, your rsynclist file may look like this:
  /tmp/share/file2  ->  /tmp/file2
  /tmp/share/file2.post -> /tmp/file2.post
  /tmp/share/file3  ->  /tmp/filex
  /tmp/share/file3.post -> /tmp/file3.post
  /tmp/myscript -> /tmp/myscript
  # the below are postscripts
  EXECUTE:
  /tmp/share/file2.post
  /tmp/share/file3.post
  EXECUTEALWAYS:
  /tmp/myscript
  APPEND:
  /custom/mypasswd -> /etc/passwd
  /custom/mygroups -> /etc/group
  /custom/myshadow -> /etc/shadow
 
 Note: no order can be assumed by the order that the EXECUTE,EXECUTEALWAYS and APPEND clause fall in the synclist file.
 
 For more information on syncing files to node, read Sync-ing_Config_Files_to_Nodes
 
 On Linux rsync always uses ssh remoteshell. On AIX, ssh or rsh is used depending on the site.useSSHonAIX attribute.
 


\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-i | -**\ **-rootimg**\  \ *install image*\ 
 
 Specifies  the path to the install image on the local Linux node.
 


\ **-o | -**\ **-node-options**\  \ *node_options*\ 
 
 Specifies options to pass to the remote shell  command  for
 node  targets.  The options must be specified within double
 quotation marks ("") to distinguish them from \ **xdsh**\  options.
 


\ **-p | -**\ **-preserve**\ 
 
 Preserves  the  source  file characteristics as implemented by
 the configured remote copy command.
 


\ **-P | -**\ **-pull**\ 
 
 Pulls (copies) the files from the targets and places  them  in
 the  target_path  directory on the local host. The target_path
 must be a directory. Files pulled from  remote  machines  have
 ._target  appended  to  the  file  name to distinguish between
 them. When the \ **-P**\  flag is used with the \ **-R**\  flag,  ._target  is
 appended to the directory. Only one file per invocation of the
 xdcp pull command can be pulled from the specified  targets.
 Hierarchy is not automatically support yet.   You must first pull
 the file to the Service Node and then pull the file to the Management 
 node.
 


\ **-q | -**\ **-show-config**\ 
 
 Displays the current environment settings for all DSH
 Utilities commands. This includes the values of all environment
 variables  and  settings  for  all  currently installed and
 valid contexts. Each setting is prefixed with  \ *context*\ :  to
 identify the source context of the setting.
 


\ **-r | -**\ **-node-rcp**\  \ *node_remote_copy*\ 
 
 Specifies  the  full  path of the remote copy command used
 for remote command execution on node targets.
 


\ **-R | -**\ **-recursive**\  \ *recursive*\ 
 
 Recursively  copies files from a local directory to the remote
 targets, or when specified with the \ **-P**\  flag, recursively pulls
 (copies)  files  from  a remote directory to the local host. A
 single source directory can be specified using the source_file
 parameter.
 


\ **-s**\  \ *synch service nodes*\ 
 
 Will only sync the files listed in the synclist (\ **-F**\ ), to the service
 nodes for the input compute node list. The files will be placed in the
 directory defined by the site.SNsyncfiledir attribute, or the default
 /var/xcat/syncfiles directory.
 


\ **-t | -**\ **-timeout**\  \ *timeout*\ 
 
 Specifies the time, in seconds, to wait for output from any
 currently executing remote targets. If no output is
 available  from  any  target in the specified \ *timeout*\ , 
 \ **xdsh**\  displays an error and terminates execution for the remote
 targets  that  failed to respond. If \ *timeout*\  is not specified,
 \ **xdsh**\  waits indefinitely to continue processing output  from
 all  remote  targets.  When specified with the \ **-i**\  flag, the
 user is prompted for an additional timeout interval to wait
 for output.
 


\ **-T | -**\ **-trace**\ 
 
 Enables trace mode. The \ **xdcp**\  command prints diagnostic
 messages to standard output during execution to each target.
 


\ **-v | -**\ **-verify**\ 
 
 Verifies each target before executing any  remote  commands
 on  the target. If a target is not responding, execution of
 remote commands for the target is canceled.
 


\ **-V | -**\ **-version**\ 
 
 Displays the \ **xdcp**\  command version information.
 



*************************************
\ **Environment**\  \ **Variables**\ 
*************************************



\ **DSH_ENVIRONMENT**\ 
 
 Specifies a file that contains environment variable
 definitions to export to the target before executing  the  remote
 command. This variable is overridden by the \ **-E**\  flag.
 


\ **DSH_FANOUT**\ 
 
 Specifies  the fanout value. This variable is overridden by
 the \ **-f**\  flag.
 


\ **DSH_NODE_OPTS**\ 
 
 Specifies the options to use for the remote  shell  command
 with  node targets only. This variable is overridden by the
 \ **-o**\  flag.
 


\ **DSH_NODE_RCP**\ 
 
 Specifies the full path of the remote copy command  to  use
 to  copy  local scripts and local environment configuration
 files to node targets.
 


\ **DSH_NODE_RSH**\ 
 
 Specifies the full path of the  remote  shell  to  use  for
 remote  command execution on node targets. This variable is
 overridden by the \ **-r**\  flag.
 


\ **DSH_NODEGROUP_PATH**\ 
 
 Specifies a colon-separated list of directories  that
 contain node group files for the \ **DSH**\  context. When the \ **-a**\  flag
 is specified in the \ **DSH**\  context,  a  list  of  unique  node
 names is collected from all node group files in the path.
 


\ **DSH_PATH**\ 
 
 Sets the command path to use on the targets. If \ **DSH_PATH**\  is
 not set, the default path defined in  the  profile  of  the
 remote \ *user_ID*\  is used.
 


\ **DSH_SYNTAX**\ 
 
 Specifies the shell syntax to use on remote targets; \ **ksh**\  or
 \ **csh**\ . If not specified, the  \ **ksh**\   syntax  is  assumed.  This
 variable is overridden by the \ **-S**\  flag.
 


\ **DSH_TIMEOUT**\ 
 
 Specifies  the  time,  in  seconds, to wait for output from
 each remote target. This variable is overridden by  the  \ **-t**\ 
 flag.
 



*******************
\ **Exit Status**\ 
*******************


Exit  values  for  each  remote copy command execution are displayed in
messages from the xdcp command, if the remote copy command exit value is
non-zero.  A  non-zero return code from a remote copy command indicates
that an error was encountered during the remote copy. If a remote  copy
command  encounters an error, execution of the remote copy on that tar-
get is bypassed.

The xdcp command exit code is 0, if  the  xdcp  command  executed  without
errors  and  all remote copy commands finished with exit codes of 0. If
internal xdcp errors occur or the remote copy commands do  not  complete
successfully,  the xdcp  command exit value is greater than 0.


****************
\ **Security**\ 
****************


The  \ **xdcp**\   command  has no security configuration requirements.  All
remote command security requirements  -  configuration,
authentication,  and authorization - are imposed by the underlying remote
command configured for \ **xdsh**\ . The command  assumes  that  authentication
and  authorization  is  configured  between  the  local host and the
remote targets. Interactive password prompting is not supported;  an
error  is displayed and execution is bypassed for a remote target if
password prompting occurs, or if either authorization or
authentication  to  the  remote  target fails. Security configurations as they
pertain to the remote environment and remote shell command are
userdefined.


****************
\ **Examples**\ 
****************



1. To copy the /etc/hosts file from all  nodes in the cluster
to the /tmp/hosts.dir directory on the local host, enter:
 
 
 .. code-block:: perl
 
   xdcp all -P /etc/hosts /tmp/hosts.dir
 
 
 A suffix specifying the name of the target is  appended  to  each
 file name. The contents of the /tmp/hosts.dir directory are similar to:
 
 
 .. code-block:: perl
 
   hosts._node1   hosts._node4   hosts._node7
   hosts._node2   hosts._node5   hosts._node8
   hosts._node3   hosts._node6
 
 


2. To copy the directory /var/log/testlogdir  from  all  targets  in
NodeGroup1 with a fanout of 12, and save each directory on  the  local
host as /var/log._target, enter:
 
 
 .. code-block:: perl
 
   xdcp NodeGroup1 -f 12 -RP /var/log/testlogdir /var/log
 
 


3. To copy  /localnode/smallfile and /tmp/bigfile to /tmp on node1
using rsync and input -t flag to rsync, enter:
 
 
 .. code-block:: perl
 
   xdcp node1 -r /usr/bin/rsync -o "-t" /localnode/smallfile /tmp/bigfile /tmp
 
 


4. To copy the /etc/hosts file from the local host to all the nodes
in the cluster, enter:
 
 
 .. code-block:: perl
 
   xdcp all /etc/hosts /etc/hosts
 
 


5. To copy all the files in /tmp/testdir from the local host to all the nodes
in the cluster, enter:
 
 
 .. code-block:: perl
 
   xdcp all /tmp/testdir/* /tmp/testdir
 
 


6. To copy all the files in /tmp/testdir and it's subdirectories 
from the local host to node1 in the cluster, enter:
 
 
 .. code-block:: perl
 
   xdcp node1 -R /tmp/testdir /tmp/testdir
 
 


7. To copy the /etc/hosts  file  from  node1  and  node2  to the
/tmp/hosts.dir directory on the local host, enter:
 
 
 .. code-block:: perl
 
   xdcp node1,node2 -P /etc/hosts /tmp/hosts.dir
 
 


8. To rsync the /etc/hosts file to your compute nodes:
 
 Create a rsync file /tmp/myrsync, with this line:
 
 /etc/hosts -> /etc/hosts
 
 or
 
 /etc/hosts -> /etc/    (last / is required)
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp compute -F /tmp/myrsync
 
 


9.
 
 To rsync all the files in /home/mikev to the  compute nodes:
 
 Create a rsync file /tmp/myrsync, with this line:
 
 /home/mikev/\* -> /home/mikev/      (last / is required)
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp compute -F /tmp/myrsync
 
 


10. To rsync to the compute nodes, using service nodes, the command will first
rsync the files to the  /var/xcat/syncfiles directory on the service nodes and then rsync the files from that directory to the compute nodes. The /var/xcat/syncfiles default directory on the service nodes, can be changed by putting a directory value in the site table SNsyncfiledir attribute.
 
 Create a rsync file /tmp/myrsync, with this line:
 
 /etc/hosts /etc/passwd -> /etc
 
 or
 
 /etc/hosts /etc/passwd -> /etc/
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp compute -F /tmp/myrsync
 
 
 to update the Compute Nodes
 


11. To rsync to the service nodes in preparation for rsyncing the compute nodes
during an install from the service node.
 
 Create a rsync file /tmp/myrsync, with this line:
 
 /etc/hosts /etc/passwd -> /etc
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp compute -s -F /tmp/myrsync
 
 
 to sync the service node for compute
 


12. To rsync the /etc/file1 and file2 to your compute nodes and rename to  filex and filey:
 
 Create a rsync file /tmp/myrsync, with these line:
 
 /etc/file1 -> /etc/filex
 
 /etc/file2 -> /etc/filey
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp compute -F /tmp/myrsync
 
 
 to update the Compute Nodes
 


13. To rsync files in the Linux image at /install/netboot/fedora9/x86_64/compute/rootimg on the MN:
 
 Create a rsync file /tmp/myrsync, with this line:
 
 /etc/hosts /etc/passwd -> /etc
 
 Run:
 
 
 .. code-block:: perl
 
   xdcp -i /install/netboot/fedora9/x86_64/compute/rootimg -F /tmp/myrsync
 
 


14. To define the Management Node in the database so you can use xdcp, run
 
 
 .. code-block:: perl
 
   xcatconfig -m
 
 



*************
\ **Files**\ 
*************



****************
\ **SEE ALSO**\ 
****************


xdsh(1)|xdsh.1, noderange(3)|noderange.3

