
######
xdsh.1
######

.. highlight:: perl


************
\ **NAME**\ 
************


\ **xdsh**\  - Concurrently runs remote commands on multiple nodes (Management Node, Service Nodes, compute nodes), or an install image.


****************
\ **SYNOPSIS**\ 
****************


\ **xdsh**\  \ *noderange*\  [\ **-B**\  | \ **-**\ **-bypass**\ ]  [\ **-**\ **-devicetype**\  \ *type_of_device*\ ] [\ **-e**\ ] [\ **-E**\  \ *environment_file*\ ]  [\ **-f**\  \ *fanout*\ ]
[\ **-L**\ ]  [\ **-l**\   \ *userID*\ ] [\ **-m**\ ] [\ **-o**\  \ *node_options*\ ] [\ **-Q**\ ] [\ **-r**\  \ *node_remote_shell*\ ] [\ **-s**\ ] [\ **-S**\  {\ **csh | ksh**\ }] [\ **-t**\  \ *timeout*\ ]
[\ **-T**\ ] [\ **-v**\ ] [\ **-X**\  \ *env_list*\ ] [\ **-z**\ ] [\ **-**\ **-sudo**\ ] \ *command_list*\ 

\ **xdsh**\  \ *noderange*\   [\ **-K**\ ]

\ **xdsh**\  \ *noderange*\   [\ **-K**\ ] [\ **-l**\   \ *userID*\ ] \ **-**\ **-devicetype**\  \ *type_of_device*\ 

\ **xdsh**\  [\ **-i**\  \ *image path | nim image name*\ ] \ *command_list*\ 

\ **xdsh**\  \ *noderange*\   [\ **-c**\ ]

\ **xdsh**\  [\ **-h**\  | \ **-V**\  | \ **-q**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **xdsh**\  command runs commands in parallel on remote nodes and/or the Management Node.   The \ **xdsh**\  command issues  a
remote shell command for each target specified, and returns the output
from all targets,
formatted so that command results  from  all  nodes  can  be  managed.
If the command is to be executed  on the Management Node, it does not use a remote shell command, but uses the local OS copy or shell command. The Management Node must be defined in the xCAT database. The best way to do this is to use the xcatconfig -m option. 
The \ **xdsh**\  command is an xCAT Distributed Shell Utility.

\ **COMMAND**\  \ **SPECIFICATION**\ :

The commands to execute on the  targets  are  specified by the
\ *command_list*\   \ **xdsh**\   parameter, or executing a local script using the \ **-e**\  flag.

The syntax for the \ *command_list*\  \ **xdsh**\  parameter is as follows:

\ *command*\ [; \ *command*\ ]...

where \ *command*\  is the command to run on the remote
target. Quotation marks are required to ensure that all commands in the
list are executed remotely, and that any special characters are interpreted
correctly on the remote target. A script file on the local host can be
executed on each of the remote targets by using the \ **-e**\  flag. If \ **-e**\  is specified, \ *command_list*\  is the
script name and arguments to the script. For example:

xdsh hostname -e \ *script_filename*\  [\ *arguments*\ ]...

The \ *script_filename*\  file is copied to a random  filename  in  the  \ **/tmp**\  directory on each remote target and then executed on the targets.

The \ **xdsh**\  command does not work with any interactive commands, including
those that read from standard input.

\ **REMOTE**\  \ **SHELL**\  \ **COMMAND**\ :

The  \ **xdsh**\   command  uses a configurable remote shell command to execute
remote commands on the remote targets. Support is  explicitly  provided
for  AIX  Remote  Shell and OpenSSH, but any secure remote command that
conforms to the IETF (Internet Engineering Task  Force)  Secure  Remote
Command Protocol can be used.

The remote shell is determined as follows, in order of precedence:

1. The \ **-r**\  flag.

2. The \ **DSH_NODE_RSH**\  environment variable.

3. The default node remote shell as defined by the target \ *context*\ .

4. The \ **/usr/bin/ssh**\  command.

The  remote shell options are determined as follows, in order of prece-
dence:

1. The \ **-o**\  flag.

2. The \ **DSH_NODE_OPTS**\  environment variable.

\ **REMOTE**\  \ **SHELL**\  \ **ENVIRONMENT**\ :

The shell environment used on the remote target defaults to  the  shell
defined for the \ *user_ID*\  on the remote target.  The command
syntax that \ **xdsh**\  uses to form the remote commands can be specified using the \ **-S**\  flag. If \ **-S**\  is not specified, the syntax defaults to \ **sh**\  syntax.

When  commands  are  executed  on  the  remote target, the path used is
determined by the \ **DSH_PATH**\  environment variable defined in the shell of
the  current  user. If \ **DSH_PATH**\  is not set, the path used is the remote
shell default path. For example, to set the local path for  the  remote
targets, use:

DSH_PATH=$PATH

The  \ **-E**\  flag exports a local environment definition file to each remote
target. Environment variables specified in this file are defined in the
remote shell environment before the \ *command_list*\  is executed.
The file should be executable and contain one environment variable per line.

\ **COMMAND**\  \ **EXECUTION**\ :

The  maximum  number  of concurrent remote shell command processes (the
fanout) can be specified with the \ **-f**\  flag or with the \ **DSH_FANOUT**\ 
environment variable. The fanout is only restricted by the number of remote
shell commands that can be run in parallel. You can experiment with the
\ **DSH_FANOUT**\   value on your management server to see if higher values are
appropriate.

A timeout value for remote command execution can be specified with  the
\ **-t**\   flag  or  with  the \ **DSH_TIMEOUT**\  environment variable. If any remote
target does not provide output to either standard  output  or  standard
error  within  the  timeout  value,  \ **xdsh**\  displays an error message and
exits.

If streaming mode is specified with the \ **-s**\  flag, output is returned  as
it  becomes available from each target, instead of waiting for the
\ *command_list*\  to complete on all targets before returning output. This  can
improve performance but causes the output to be unsorted.

The  \ **-z**\  flag displays the exit code from the last command issued on the
remote node in \ *command_list*\ . Note that OpenSSH behaves differently;  it
returns  the  exit status of the last remote command issued as its exit
status. If  the  command  issued  on the remote node is run in the
background, the exit status is not displayed.

The \ **-m**\  flag monitors execution of the \ **xdsh**\  command by  printing  status
messages to standard output. Each status message is preceded by \ **dsh**\ .

The \ **-T**\  flag provides diagnostic trace information for the execution of
the \ **xdsh**\  command. Default settings and the actual remote shell commands
executed on the remote targets are displayed.

No error detection  or recovery mechanism is provided for remote
targets. The \ **xdsh**\  command output to standard error and standard output can
be analyzed to determine the appropriate course of action.

\ **COMMAND**\  \ **OUTPUT**\ :

The  \ **xdsh**\   command  waits  until complete output is available from each
remote shell process and then displays that  output  before  initiating
new  remote shell processes. This default behavior is overridden by the
\ **-s**\  flag.

The \ **xdsh**\  command output consists of standard error and standard  output
from the remote commands. The \ **xdsh**\  standard output is the standard
output from the remote shell command. The \ **xdsh**\  standard error is the
standard  error  from the remote shell command.  Each line is prefixed with
the host name of the node that produced the output. The  host  name  is
followed  by  the  \ **:**\   character and a command output line. A filter for
displaying identical outputs grouped by node  is  provided  separately.
See the \ **xdshbak**\  command for more information.

A  command  can  be run silently using the \ **-Q**\  flag; no output from each
target's standard output or standard error is displayed.

\ **SIGNALS**\ :

Signal 2 (INT), Signal 3 (QUIT), and Signal 15 (TERM) are propagated to
the commands executing on the remote targets.

Signal  19  (CONT),  Signal  17 (STOP), and Signal 18 (TSTP) default to
\ **xdsh**\ ; the \ **xdsh**\  command responds normally to these signals, but the
signals  do  not have an effect on remotely executing commands. Other
signals are caught by \ **xdsh**\  and have their default effects on the \ **xdsh**\ 
command; all current child processes, through propagation to remotely
running commands, are terminated (SIGTERM).


***************
\ **OPTIONS**\ 
***************



\ **-B | -**\ **-bypass**\ 
 
 Runs in bypass mode, use if the xcatd daemon is hung.
 


\ **-c | -**\ **-cleanup**\ 
 
 This flag will have xdsh remove all files from the subdirectories of the
 the directory on the servicenodes, where xdcp stages the copy to the 
 compute nodes as defined in the site table SNsyncfiledir and nodesyncfiledir
 attribute, when the target is a service node.
 
 It can also be used to remove the nodesyncfiledir directory on the compute 
 nodes, which keeps the backup copies of files for the xdcp APPEND function
 support, if a compute node is the target.
 


\ **-e | -**\ **-execute**\ 
 
 Indicates  that \ *command_list*\  specifies a local script
 filename and arguments to be executed on  the  remote  targets.
 The  script  file  is copied to the remote targets and then
 remotely   executed   with   the   given   arguments.   The
 \ **DSH_NODE_RCP**\   environment variables specify the remote copy
 command to use to copy the script file to node targets.
 


\ **-E | -**\ **-environment**\  \ *environment_file*\ 
 
 Specifies that the  \ *environment_file*\   contains  environment
 variable definitions to export to the target before
 executing the  \ *command_list*\ .
 


\ **-**\ **-devicetype**\  \ *type_of_device*\ 
 
 Specify a user-defined device type that references the location
 of relevant device configuration file. The devicetype value must
 correspond to a valid device configuration file.
 xCAT ships some default configuration files
 for Ethernet switches and and IB switches under 
 \ */opt/xcat/share/xcat/devicetype*\  directory. If you want to overwrite
 any of the configuration files, copy them to \ */var/opt/xcat/*\ 
 directory and cutomize. 
 For example, \ *base/IBSwitch/Qlogic/config*\  is the configuration
 file location if devicetype is specified as IBSwitch::Qlogic.
 xCAT will first search config file using \ */var/opt/xcat/*\  as the base. 
 If not found, it will search for it using  
 \ */opt/xcat/share/xcat/devicetype/*\  as the base.
 


\ **-f | -**\ **-fanout**\  \ *fanout_value*\ 
 
 Specifies a fanout value for the maximum number of  concurrently  executing  remote shell processes. Serial execution can be specified by indicating a fanout value of \ **1**\ . If  \ **-f**\  is not specified, a default fanout value of \ **64**\  is used.
 


\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-i | -**\ **-rootimg**\  \ *install image*\ 
 
 For Linux, Specifies the path to the install image on the local node.
 For AIX, specifies the name of the osimage on the local node. Run lsnim 
 for valid names.
 xdsh will chroot (xcatchroot for AIX) to this path and run the xdsh command against the
 install image.  No other xdsh flags, environment variables apply with 
 this input.  A noderange is not accepted. Only runs on the local host, 
 normally the Management Node. The command you run must not prompt for input, the prompt will not be returned to you, and it will appear that xdsh hangs.
 


\ **-K | -**\ **-ssh-setup**\ 



\ **-K | -**\ **-ssh-setup**\   \ **-l | -**\ **-user**\  \ *user_ID*\  \ **-**\ **-devicetype**\  \ *type_of_device*\ 
 
 Set up the SSH keys for the user running the command to the specified node list.
 The userid must have the same uid, gid and password as the userid on the node
 where the keys will be setup.
 
 If the current user is root,  roots public ssh keys will be put in the
 authorized_keys\* files under roots .ssh directory on the node(s).
 If the current user is non-root, the user must be in the policy table and have credential to run the xdsh command.
 The non-root users public ssh keys and root's public ssh keys will be put in
 the authorized_keys\* files under the non-root users .ssh directory on the node(s).
 Other device types, such as IB switch, are also supported.  The
 device should be defined as a node and nodetype should be defined 
 as switch before connecting.
 The \ **xdsh -K**\  command must be run from the Management Node.
 


\ **-l | -**\ **-user**\  \ *user_ID*\ 
 
 Specifies a remote user name to use for remote command execution.
 


\ **-L | -**\ **-no-locale**\ 
 
 Specifies to not export the locale definitions of the local
 host to the remote targets. Local host  locale  definitions
 are exported by default to each remote target.
 


\ **-m | -**\ **-monitor**\ 
 
 Monitors  remote  shell execution by displaying status
 messages during execution on each target.
 


\ **-o | -**\ **-node-options**\  \ *node_options*\ 
 
 Specifies options to pass to the remote shell  command  for
 node  targets.  The options must be specified within double
 quotation marks ("") to distinguish them from \ **xdsh**\  options.
 


\ **-q | -**\ **-show-config**\ 
 
 Displays the current environment settings for all DSH
 Utilities commands. This includes the values of all environment
 variables  and  settings  for  all  currently installed and
 valid contexts. Each setting is prefixed with  \ *context*\ :  to
 identify the source context of the setting.
 


\ **-Q | -**\ **-silent**\ 
 
 Specifies silent mode. No target output is written to standard output or  standard  error.  Monitoring  messages are written to standard output.
 


\ **-r | -**\ **-node-rsh**\  \ *node_remote_shell*\ 
 
 Specifies the path of the remote shell command used
 for remote command execution on node targets.
 


\ **-s | -**\ **-stream**\ 
 
 Specifies that output is returned as it  becomes  available
 from  each  target, instead of waiting for the \ *command_list*\ 
 to be completed on a target before returning output.
 


\ **-S | -**\ **-syntax**\  {\ **csh | ksh**\ }
 
 Specifies the shell syntax to be used on the remote target.
 If not specified, the \ **ksh**\  syntax is used.
 


\ **-**\ **-sudo**\ 
 
 Adding the \ **-**\ **-sudo**\  flag to the xdsh command will have xdsh run sudo before
 running the command.  This is particular useful when using the \ **-e**\  option.
 This is required when you input \ **-l**\  with a non-root user id and want that id
 to be able to run as root on the node.  The non-root userid will must be 
 previously defined as an xCAT user, see process for defining non-root ids in
 xCAT and setting up for using xdsh.  The userid sudo setup will have 
 to be done by the admin on the node.  This includes, allowing all commands that
 you would like to run with xdsh by using visudo to edit the /etc/sudoers file.
 You must disabl ssh tty requirements by commenting out or removing this line in the /etc/sudoes file "#Defaults    requiretty". 
 See the document Granting_Users_xCAT_privileges for sudo setup requirements.
 This is not supported in a hierarical cluster, that is the nodes are serviced by servicenodes.
 


\ **-t | -**\ **-timeout**\  \ *timeout*\ 
 
 Specifies the time, in seconds, to wait for output from any
 currently executing remote targets. If no output is
 available  from  any  target in the specified \ *timeout*\ , \ **xdsh**\ 
 displays an error and terminates execution for the remote
 targets  that  failed to respond. If \ *timeout*\  is not specified,
 \ **xdsh**\  waits indefinitely to continue processing output  from
 all  remote  targets. The exception is the -K flag which defaults 
 to  10 seconds.
 


\ **-T | -**\ **-trace**\ 
 
 Enables trace mode. The \ **xdsh**\  command prints diagnostic
 messages to standard output during execution to each target.
 


\ **-v | -**\ **-verify**\ 
 
 Verifies each target before executing any  remote  commands
 on  the target. If a target is not responding, execution of
 remote commands for the target is canceled. When  specified
 with the \ **-i**\  flag, the user is prompted to retry the
 verification request.
 


\ **-V | -**\ **-version**\ 
 
 Displays the \ **xdsh**\  command version information.
 


\ **-X**\  \ *env_list*\ 
 
 Ignore \ **xdsh**\  environment variables. This option can take  an
 argument  which  is  a  comma separated list of environment
 variable names that should \ **NOT**\  be ignored. If there  is  no
 argument  to  this  option,  or  the  argument  is an empty
 string, all \ **xdsh**\  environment variables will be ignored.
 This option is useful when running \ **xdsh**\  from within other
 scripts when you don't want the user's environment affecting
 the behavior of xdsh.
 


\ **-z | -**\ **-exit-status**\ 
 
 Displays the exit status for  the  last  remotely  executed
 non-asynchronous  command  on  each  target. If the command
 issued on the remote node is run  in  the  background,  the
 exit status is not displayed.
 
 Exit  values  for  each remote shell execution are displayed in
 messages from the \ **xdsh**\  command, if the remote  shell  exit  values  are
 non-zero.  A non-zero return code from a remote shell indicates that
 an error was encountered in the remote shell. This  return  code  is
 unrelated  to  the  exit  code  of the remotely issued command. If a
 remote shell encounters an error, execution of the remote command on
 that target is bypassed.
 
 The  \ **xdsh**\   command  exit  code  is \ **0**\  if the command executed without
 errors and all remote shell commands finished with exit codes of  \ **0**\ .
 If  internal  \ **xdsh**\   errors occur or the remote shell commands do not
 complete successfully, the \ **xdsh**\  command exit value is  greater  than
 \ **0**\ .  The exit value is increased by \ **1**\  for each successive instance of
 an unsuccessful remote command execution.  If  the  remotely  issued
 command  is  run  in  the  background, the exit code of the remotely
 issued command is \ **0**\ .
 



*************************************
\ **Environment**\  \ **Variables**\ 
*************************************



\ **DEVICETYPE**\ 
 
 Specify a user-defined device type.  See \ **-**\ **-devicetype**\  flag.
 


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
 


\ **DSH_PATH**\ 
 
 Sets the command path to use on the targets. If \ **DSH_PATH**\  is
 not set, the default path defined in  the  profile  of  the
 remote \ *user_ID*\  is used.
 


\ **DSH_REMOTE_PASSWORD**\ 
 
 If \ **DSH_REMOTE_PASSWORD**\  is set to the password of the
 userid (usually root) that will ssh to the node, then when
 you use the -K flag, you will  not be prompted for a password.
 


\ **DSH_SYNTAX**\ 
 
 Specifies the shell syntax to use on remote targets; \ **ksh**\  or
 \ **csh**\ . If not specified, the  \ **ksh**\   syntax  is  assumed.  This
 variable is overridden by the \ **-S**\  flag.
 


\ **DSH_TIMEOUT**\ 
 
 Specifies  the  time,  in  seconds, to wait for output from
 each remote target. This variable is overridden by  the  \ **-t**\ 
 flag.
 



**********************************
\ **Compatibility with AIX dsh**\ 
**********************************


To provide backward compatibility for scripts written using dsh in
AIX and CSM, a tool has been provided \ **groupfiles4dsh**\ ,
which will build node group files from the
xCAT database that can be used by dsh. See \ **man groupfiles4dsh**\ .


****************
\ **SECURITY**\ 
****************


The  \ **xdsh**\   command  has no security configuration requirements.  All
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


*******************
\ **EXIT STATUS**\ 
*******************


The dsh command exit code is 0 if the command executed without errors and all remote shell commands finished with exit codes of 0. If internal dsh errors occur or the remote shell commands do not complete successfully, the dsh command exit value is greater than 0. The exit value is increased by 1 for each successive instance of an unsuccessful remote command execution.  If the remotely issued command is run in the background, the exit code of the remotely issued command is 0.


****************
\ **EXAMPLES**\ 
****************



1. To set up the SSH keys for root on node1, run as root:
 
 
 .. code-block:: perl
 
   xdsh node1 -K
 
 


2. To run the \ **ps -ef**\  command on node targets \ **node1**\  and \ **node2**\ , enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2 "ps -ef"
 
 


3. To run the \ **ps**\  command on node targets \ **node1**\  and run the remote command with the -v and -t flag, enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2  -o "-v -t" ps
 
 


4. To execute the commands contained in \ **myfile**\  in the \ **XCAT**\ 
context on several node targets, with a fanout of \ **1**\ , enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2 -f 1 -e myfile
 
 


5. To run the ps command on node1 and ignore all the dsh
environment variable except the DSH_NODE_OPTS, enter:
 
 
 .. code-block:: perl
 
   xdsh node1 -X `DSH_NODE_OPTS' ps
 
 


6. To run on Linux, the xdsh command "rpm -qa | grep xCAT" 
on the service node fedora9 diskless image, enter:
 
 
 .. code-block:: perl
 
   xdsh -i /install/netboot/fedora9/x86_64/service/rootimg "rpm -qa | grep xCAT"
 
 


7. To run on AIX, the xdsh command "lslpp -l | grep bos" on the NIM 611dskls spot, enter:
 
 
 .. code-block:: perl
 
   xdsh -i 611dskls "/usr/bin/lslpp -l | grep bos"
 
 


8. To cleanup the servicenode directory that stages the copy of files to the nodes, enter:
 
 
 .. code-block:: perl
 
   xdsh servicenoderange -c
 
 


9.
 
 To define the QLogic IB switch as a node and to set up the SSH keys for IB switch 
 \ **qswitch**\  with device configuration file
 \ **/var/opt/xcat/IBSwitch/Qlogic/config**\  and user name \ **username**\ , Enter
 
 
 .. code-block:: perl
 
   chdef -t node -o qswitch groups=all nodetype=switch
  
   xdsh qswitch -K -l username --devicetype IBSwitch::Qlogic
 
 


10. To define the Management Node  in the database so you can use xdsh, Enter
 
 
 .. code-block:: perl
 
   xcatconfig -m
 
 


11. To define the Mellanox switch as a node and run a command to show the ssh keys. 
\ **mswitch**\  with and user name \ **username**\ , Enter
 
 
 .. code-block:: perl
 
   chdef -t node -o mswitch groups=all nodetype=switch
  
   xdsh mswitch -l admin --devicetype IBSwitch::Mellanox  'enable;configure terminal;show ssh server host-keys'
 
 


12.
 
 To define a BNT Ethernet switch as a node and run a command to create a new vlan with vlan id 3 on the switch.
 
 
 .. code-block:: perl
 
   chdef myswitch groups=all
  
   tabch switch=myswitch switches.sshusername=admin switches.sshpassword=passw0rd switches.protocol=[ssh|telnet]
 
 
 where \ *admin*\  and \ *passw0rd*\  are the SSH user name and password for the switch.
 
 If it is for Telnet, add \ *tn:*\  in front of the user name: \ *tn:admin*\ .
 
 
 .. code-block:: perl
 
   dsh myswitch --devicetype EthSwitch::BNT 'enable;configure terminal;vlan 3;end;show vlan'
 
 


13.
 
 To run xdsh with the non-root userid "user1" that has been setup as an xCAT userid and with sudo on node1 and node2 to run as root, do the following, see xCAT doc on Granting_Users_xCAT_privileges:
 
 
 .. code-block:: perl
 
   xdsh node1,node2 --sudo -l user1 "cat /etc/passwd"
 
 



*************
\ **Files**\ 
*************



****************
\ **SEE ALSO**\ 
****************


xdshbak(1)|xdshbak.1, noderange(3)|noderange.3, groupfiles4dsh(1)|groupfiles4dsh.1

