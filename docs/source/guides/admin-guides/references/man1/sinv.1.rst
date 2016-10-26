
######
sinv.1
######

.. highlight:: perl


************
\ **NAME**\ 
************


\ **sinv**\  - Checks the software configuration of the nodes in the cluster.


****************
\ **SYNOPSIS**\ 
****************


\ **sinv**\   [\ **-o**\  \ *output*\ ] [\ **-p**\  \ *template path*\ ] [\ **-t**\  \ *template count*\ ] [\ **-s**\  \ *seed node*\ ] [\ **-i**\ ] [\ **-e**\ ] [\ **-r**\ ] [\ **-V**\ ] [\ **-**\ **-devicetype**\  \ *type_of_device*\ ]  [\ **-l**\   \ *userID*\ ] [[\ **-f**\  \ *command file*\ ] | [\ **-c**\  \ *command*\ ]]

\ **sinv**\  [\ **-h**\  | \ **-v**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The \ **sinv**\  command is designed to check the configuration of the nodes in a cluster.
The command takes as input command line flags, and one or more templates which will be compared against the output of the xdsh command, designated to be run by the -c or -f flag, on the nodes in the noderange.

The nodes will then be grouped according to the template they match and a report returned to the administrator in the output file designated by the -o flag, or to stdout.

\ **sinv**\  supports checking the output from the  \ **rinv**\  or \ **xdsh**\  command.

The \ **sinv**\  command is an xCAT Distributed Shell Utility.

\ **COMMAND**\  \ **SPECIFICATION**\ :

The xdsh or rinv command to execute on the remote targets is specified by the \ **-c**\  flag, or by the \ **-f**\  flag
which is followed by the fully qualified path to a file containing the command.

Note: do not add | xdshcoll to the command on the command line or in the
command file, it is automatically added by sinv.

The syntax for the \ **-c**\   \ **sinv**\  parameter is as follows:

"\ *command*\ [; \ *command*\ ]..."

where \ *command*\  is the command to run on the remote
target. Quotation marks are required to ensure that all commands in the
list are executed remotely, and that any special characters are interpreted
correctly on the remote target.

The \ **sinv**\  command does not work with any interactive commands, including
those that read from standard input.

\ **REMOTE**\  \ **SHELL**\  \ **COMMAND**\ :

For xdsh, support is  explicitly  provided
for  AIX  Remote  Shell and OpenSSH, but any secure remote command that
conforms to the IETF (Internet Engineering Task  Force)  Secure  Remote
Command Protocol can be used. See man \ **xdsh**\  for more details.


***************
\ **OPTIONS**\ 
***************



\ **-o | -**\ **-output**\  \ *report output file*\ 
 
 Optional output file. This is the location of the file that will contain the report of the nodes that match, and do not match, the input templates.
 If the flag is not used, the output will go to stdout.
 


\ **-p | -**\ **-tp**\  \ *template path*\ 
 
 This is the path to the template file. The template contains the output
 of xdsh command, that has been run against a "seed" node, a node 
 that contains the configuration that you would like  
 all nodes in your noderange to match.
 
 The admin can create the template by running the xdsh command on
 the seed node, pipe to xdshcoll ( required) and store the output
 in the template path. See examples.
 
 \ **Note:**\  The admin can also edit the
 template to remove any lines that they do not want checked.
 
 An alternative method is to use the [\ **-s**\  \ *seed node*\ ] parameter, 
 which will automatically build the template for you from the 
 seed node named.
 
 If a template path file does not exist, and a seed node is not input,
 then sinv will automatically use the one node in the noderange as
 the seed node and build the template.
 


\ **-t | -**\ **-tc**\  \ *template count*\ 
 
 This count is the number of templates that the command will use
 to check for nodes matches.  If the template in the template path does not
 match a node, the \ **sinv**\  will check additional templates  up 
 to the template count.
 
 For each node, it will compare the node against each template to see if 
 there is a match.  
 If there is no match, and we are not over the template count,
 then a new template will be created from the node output. 
 This will result in having all nodes that match a given template reported in
 their group at the end of the run in the output file. 
 If no template count is specified,  0 is the default, and all nodes will
 be compared against the first template.
 


\ **-s | -**\ **-seed**\  \ *seed node*\ 
 
 This is the node that will be used to build the first template
 that is stored in template path.  You can use this parameter instead of running
 the command yourself to build the template.
 
 \ **Note:**\  If the template path file does not exists, and no seed node is 
 supplied, the seed node automatically is one node in the
 noderange.
 


\ **-i | -**\ **-ignorefirst**\ 
 
 This flag suppresses the reporting of the nodes matching the first
 template. In very large systems, you may not want to show the nodes that
 have the correct configuration, since the list could contain thousands of nodes.
 This allows you to only report the nodes that do not match the required 
 configuration.
 


\ **-e | -**\ **-exactmatch**\ 
 
 This requires the check of node output against template to be an exact match.
 If this flag is not set, \ **sinv**\  checks to see if the return from the 
 xdsh command to the nodes contain a match for each line in the input 
 template (except for xdshcoll header and comments). If not in exactmatch mode,
 there can exist more lines in the xdsh return from the nodes.
 
 For example, if running a "rpm -qa | grep xCAT" command, without exactmatch 
 set, if the node containes more xCAT rpms that listed in the template,
 it would be considered a match, as long as all rpms listed in the template
 were on the node. With exactmatch set, the output must be identical 
 to the template.
 


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
 


\ **-l | -**\ **-user**\  \ *user_ID*\ 
 
 Specifies a remote user name to use for remote command execution.
 


\ **-c | -**\ **-command**\ 
 
 The xdsh or rinv command that will be run. The command should be enclosed in 
 double quotes to insure correct shell interpretation. This parameter must only contain, the node range or the image path (Linux) or spot name for AIX. It cannot be used to set additional input flags to xdsh or rinv (for example -s,-T,-e).  See examples below.
 
 \ **Note:**\  do not add the | xdshcoll to the command,
 it is automatically added by sinv.  sinv also automatically sets the -v flag for xdsh.
 


\ **-f | -**\ **-file**\ 
 
 The file containing the xdsh or rinv command that will be run. 
 This should be the fully qualified name of the file.
 
 \ **Note:**\  do not add the | xdshcoll to the command in the file,
 it is automatically added by sinv.
 


\ **-r | -**\ **-remove**\ 
 
 This flag indicates that generated templates should be removed at the
 at the end of the \ **sinv**\  command execution.
 
 If the flag is input, then all templates that are generated by the \ **sinv**\ 
 command, will be removed. If the first template is created by the admin,
 it will not be removed.
 
 If the flag is not input, no
 templates will be removed. It is up to the admin to cleanup templates.
 


\ **-h | -**\ **-help**\ 
 
 Displays usage information.
 


\ **-v | -**\ **-version**\ 
 
 Displays xCAT release version.
 


\ **-V | -**\ **-Verbose**\ 
 
 Verbose mode.
 



****************
\ **Examples**\ 
****************



1. To setup sinv.template (name optional) for input to the \ **sinv**\  command , enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2 "rpm -qa | grep ssh " | xdshcoll  > /tmp/sinv.template
 
 
 Note: when setting up the template the output of xdsh must be piped to xdshcoll, sinv processing depends on it.
 


2. To setup rinv.template for input to the \ **sinv**\  command , enter:
 
 
 .. code-block:: perl
 
   rinv node1-node2 serial | xdshcoll  > /tmp/rinv.template
 
 
 Note: when setting up the template the output of rinv must be piped to xdshcoll, sinv processing depends on it.
 


3. To execute \ **sinv**\  using the sinv.template generated above
on the nodegroup, \ **testnodes**\  ,possibly generating up to two
new templates, and removing all generated templates in the end, and writing
output report to /tmp/sinv.output, enter:
 
 
 .. code-block:: perl
 
   sinv -c "xdsh testnodes rpm -qa | grep ssh" -p /tmp/sinv.template -t 2 -r -o /tmp/sinv.output
 
 
 Note: do not add the pipe to xdshcoll on the -c flag, it is automatically added by the sinv routine.
 


4. To execute \ **sinv**\  on noderange, node1-node4, using the seed node, node8,
to generate the first template, using the xdsh command (-c),
possibly generating up to two additional
templates and not removing any templates at the end, enter:
 
 
 .. code-block:: perl
 
   sinv -c "xdsh node1-node4 lslpp -l | grep bos.adt" -s node8 -p /tmp/sinv.template -t 2 -o /tmp/sinv.output
 
 


5. To execute \ **sinv**\  on noderange, node1-node4, using the seed node, node8,
to generate the first template, using the rinv command (-c),
possibly generating up to two additional
templates and removing any generated templates at the end, enter:
 
 
 .. code-block:: perl
 
   sinv -c "rinv node1-node4 serial" -s node8 -p /tmp/sinv.template -t 2 -r -o /tmp/rinv.output
 
 


6. To execute \ **sinv**\  on noderange, node1-node4, using node1 as
the seed node, to generate the sinv.template from the xdsh command (-c),
using the exact match option, generating no additional templates, enter:
 
 
 .. code-block:: perl
 
   sinv -c "xdsh node1-node4 lslpp -l | grep bos.adt" -s node1 -e -p /tmp/sinv.template  -o /tmp/sinv.output
 
 
 Note: the /tmp/sinv.template file must be empty, otherwise it will be used
 as an admin generated template.
 


7. To execute \ **sinv**\  on the Linux osimage defined for cn1.  First build a template from the /etc/hosts on the node. Then run sinv to compare.
 
 
 .. code-block:: perl
 
   xdsh cn1 "cat /etc/hosts" | xdshcoll > /tmp/sinv2/template"
  
   sinv -c "xdsh -i /install/netboot/rhels6/ppc64/test_ramdisk_statelite/rootimg cat /etc/hosts" -e -t1 -p /tmp/sinv.template -o /tmp/sinv.output
 
 


8.
 
 To execute \ **sinv**\  on the AIX NIM 611dskls spot and compare /etc/hosts to compute1 node, run the following:
 
 
 .. code-block:: perl
 
   xdsh compute1 "cat /etc/hosts" | xdshcoll > /tmp/sinv2/template"
  
   sinv -c "xdsh -i 611dskls cat /etc/hosts" -e -t1 -p /tmp/sinv.template -o /tmp/sinv.output
 
 


9.
 
 To execute \ **sinv**\  on the device mswitch2 and compare to mswitch1
 
 
 .. code-block:: perl
 
   sinv -c "xdsh mswitch  enable;show version" -s mswitch1 -p /tmp/sinv/template --devicetype IBSwitch::Mellanox -l admin -t 2
 
 


\ **Files**\ 

\ **/opt/xcat/bin/sinv/**\ 

Location of the sinv command.


****************
\ **SEE ALSO**\ 
****************


L <xdsh(1)|xdsh.1>, noderange(3)|noderange.3

