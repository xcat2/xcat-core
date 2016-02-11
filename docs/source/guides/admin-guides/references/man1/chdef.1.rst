
#######
chdef.1
#######

.. highlight:: perl


****
NAME
****


\ **chdef**\  - Change xCAT data object definitions.


********
SYNOPSIS
********


\ **chdef**\  [\ **-h | -**\ **-help**\ ] [\ **-t**\  \ *object-types*\ ]

\ **chdef**\  [\ **-t**\  \ *object-types*\ ] [\ **-o**\  \ *object-names*\ ] [\ **-n**\  \ *new-name*\ ] [\ *node*\ ]

\ **chdef**\  [\ **-V | -**\ **-verbose**\ ] [\ **-t**\  \ *object-types*\ ] [\ **-o**\  \ *object-names*\ ]
[\ **-d | -**\ **-dynamic**\ ] [\ **-p | -**\ **-plus**\ ] [\ **-m | -**\ **-minus**\ ] [\ **-z | -**\ **-stanza**\ ]
[[\ **-w**\  \ *attr*\ ==\ *val*\ ] [\ **-w**\  \ *attr*\ =~\ *val*\ ] ...] [\ *noderange*\ ] [\ *attr=val*\  [\ *attr=val...*\ ]] [\ **-u**\  [\ **provmethod=**\  {\ **install**\  | \ **netboot**\  | \ **statelite**\ }] [\ **profile=**\ \ *xxx*\ ] [\ **osvers**\ =\ *value*\ ] [\ **osarch**\ =\ *value*\ ]]


***********
DESCRIPTION
***********


This command is used to change xCAT object definitions which are stored in the xCAT database.  The default is to replace any existing attribute value with the one specified on the command line. The command will also create a new definition if one doesn't exist.

This command also can be used to change the xCAT object name to a new name. Note: the site,monitoring types can NOT be supported.


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=val pairs must be specified last on the command line. Use the help option to get a list of valid attributes for each object type.
 


\ **-d|-**\ **-dynamic**\ 
 
 Use the dynamic option to change dynamic node groups definition. This option must be used with -w option.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-m|-**\ **-minus**\ 
 
 If the value of the attribute is a list then this option may be used to remove one or more items from the list.
 


\ **-n**\  \ *new-name*\ 
 
 Change the current object name to the new-name which is specified by the -n option.
 Objects of type site, group and monitoring cannot be renamed with the -n option.
 Note: For the \ **-n**\  option, only one node can be specified. For some special nodes such as fsp, bpa, frame, cec etc., their name is referenced in their own hcp attribute, or the hcp attribute of other nodes. If you use \ **-n**\  option, you must manually change all hcp attributes that refer to this name.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. (must be the first parameter) See the "noderange" man page for details on supported formats.
 


\ **-o**\  \ *object-names*\ 
 
 A set of comma delimited object names.
 


\ **-p|-**\ **-plus**\ 
 
 This option will add the specified values to the existing value of the attribute.  It will create a comma-separated list of values.
 


\ **-t**\  \ *object-types*\ 
 
 A set of comma delimited object types.  Use the help option to get a list of valid object types.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-w**\  \ *attr==val*\  \ **-w**\  \ *attr=~val*\  ...
 
 Use one or multiple -w flags to specify the selection string that can be used to select objects. The operators ==, !=, =~ and !~ are available. Use the help option to get a list of valid attributes for each object type.
 
 Operator descriptions:
         ==        Select nodes where the attribute value is exactly this value.
         !=        Select nodes where the attribute value is not this specific value.
         =~        Select nodes where the attribute value matches this regular expression.
         !~        Select nodes where the attribute value does not match this regular expression.
 
 Note: the operator !~ will be parsed by shell, if you want to use !~ in the selection string, use single quote instead. For example:-w 'mgt!~ipmi'.
 


\ **-z|-**\ **-stanza**\ 
 
 Indicates that the file being piped to the command is in stanza format. See the xcatstanzafile man page for details on using xCAT stanza files.
 


\ **-u**\ 
 
 Fill in the attributes such as template file, pkglist file and otherpkglist file of osimage object based on the specified parameters. It will search "/install/custom/" directory first, and then "/opt/xcat/share/".
 
 Note: this option only works for objtype \ **osimage**\ .
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To change a site definition.
 
 
 .. code-block:: perl
 
   chdef -t site -o clustersite installdir=/xcatinstall
 
 


2.
 
 To change a basic node definition.
 
 
 .. code-block:: perl
 
   chdef -t node -o node01 groups="all,aix"
 
 
 (The group definitions are also created if they don't already exist.)
 


3.
 
 To add another group to the "groups" attribute in the previous example.
 
 
 .. code-block:: perl
 
   chdef -p -t node -o node01 groups="compute"
 
 


4.
 
 To remove the "all" group from the "groups" attribute in the previous example.
 
 
 .. code-block:: perl
 
   chdef -m -t node -o node01 groups="all"
 
 


5.
 
 To replace the current "groups" attribute value of "node01".
 
 
 .. code-block:: perl
 
   chdef -t node -o node01 groups="linux"
 
 


6.
 
 To add "node01" to the "members" attribute of a group definition called "LinuxNodes".
 
 
 .. code-block:: perl
 
   chdef -p -t group -o LinuxNodes members="node01"
 
 


7.
 
 To update a set of definitions based on information contained in the stanza file mystanzafile.
 
 
 .. code-block:: perl
 
   cat mystanzafile | chdef -z
 
 


8.
 
 To update a dynamic node group definition to add the cons=hmc wherevals pair.
 
 
 .. code-block:: perl
 
   chdef -t group -o dyngrp -d -p -w cons==hmc
 
 


9.
 
 To change the node object name from node1 to node2.
 
 
 .. code-block:: perl
 
   chdef -t node -o node1 -n node2
 
 


10.
 
 To change the node hwtype, this command will change the value of ppc.nodetype.
 
 
 .. code-block:: perl
 
   chdef -t node -o node1 hwtype=lpar
 
 


11.
 
 To change the policy table for policy number 7.0 for admin1
 
 
 .. code-block:: perl
 
   chdef -t policy -o 7.0 name=admin1 rule=allow
 
 


12.
 
 To change the node nic attributes
 
 
 .. code-block:: perl
 
   chdef -t node -o cn1 nicips.eth0="1.1.1.1|1.2.1.1" nicnetworks.eth0="net1|net2" nictypes.eth0="Ethernet"
 
 


13.
 
 To update an osimage definition.
 
 
 .. code-block:: perl
 
   chdef redhat6img -u provmethod=install
 
 



*****
FILES
*****


$XCATROOT/bin/chdef

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mkdef(1)|mkdef.1, lsdef(1)|lsdef.1, rmdef(1)|rmdef.1, xcatstanzafile(5)|xcatstanzafile.5

