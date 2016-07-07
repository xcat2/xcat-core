
#######
mkdef.1
#######

.. highlight:: perl


****
NAME
****


\ **mkdef**\  - Use this command to create xCAT data object definitions.


********
SYNOPSIS
********


\ **mkdef**\  [\ **-h | -**\ **-help**\ ] [\ **-t**\  \ *object-types*\ ]

\ **mkdef**\  [\ **-V | -**\ **-verbose**\ ] [\ **-t**\  \ *object-types*\ ] [\ **-**\ **-template**\  \ *template-object-name*\ ] [\ **-o**\  \ *object-names*\ ] [\ **-z | -**\ **-stanza**\ ] [\ **-d | -**\ **-dynamic**\ ] [\ **-f | -**\ **-force**\ ] [[\ **-w**\  \ *attr*\ ==\ *val*\ ] [\ **-w**\  \ *attr*\ =~\ *val*\ ] ...] [\ *noderange*\ ] [\ *attr*\ =\ *val*\  [\ *attr*\ =\ *val...*\ ]] [\ **-u**\  \ **provmethod**\ ={\ **install**\  | \ **netboot**\  | \ **statelite**\ } \ **profile=**\  \ *xxx*\  [\ **osvers=**\  \ *value*\ ] [\ **osarch=**\  \ *value*\ ]]


***********
DESCRIPTION
***********


This command is used to create xCAT object definitions which are stored in the xCAT database. If the definition already exists it will return an error message. The force option may be used to re-create a definition.  In this case the old definition will be remove and the new definition will be created.


*******
OPTIONS
*******



\ *attr=val [attr=val ...]*\ 
 
 Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=val pairs must be specified last on the command line. Use the help option to get a list of valid attributes for each object type.
 
 Note: when creating node object definitions, the 'groups' attribute is required.
 


\ **-d|-**\ **-dynamic**\ 
 
 Use the dynamic option to create dynamic node groups. This option must be used with -w option.
 


\ **-f|-**\ **-force**\ 
 
 Use the force option to re-create object definitions. This option removes the old definition before creating the new one.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. (must be the first parameter) See the "noderange" man page for details on supported formats.
 


\ **-o**\  \ *object-names*\ 
 
 A set of comma delimited object names.
 


\ **-t**\  \ *object-types*\ 
 
 A set of comma delimited object types.  Use the help option to get a list of valid object types.
 


\ **-**\ **-template**\  \ *template-object-name*\ 
 
 Name of the xCAT shipped object definition template or an existing object, from which the new object definition will be created. The newly created object will inherit the attributes of the template definition unless the attribute is specified in the arguments of \ **mkdef**\  command. If there are a template and an existing object with the same name \ *template-object-name*\ , the tempalte object takes precedence over the existing object. For the details of xCAT shipped object definition templates, refer to the manpage of \ **-**\ **-template**\  option in lsdef(1)|lsdef.1.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-w**\  \ *attr==val*\  \ **-w**\  \ *attr=~val*\  ...
 
 Use one or multiple -w flags to specify the selection string that can be used to select objects. The operators ==, !=, =~ and !~ are available. For mkdef commmand, the -w flag only makes sense for creating dynamic node group. Use the help option to get a list of valid attributes for each object type.
 
 Operator descriptions:
         ==        Select nodes where the attribute value is exactly this value.
         !=        Select nodes where the attribute value is not this specific value.
         =~        Select nodes where the attribute value matches this regular expression.
         !~        Select nodes where the attribute value does not match this regular expression.
 
 Note: if the "val" fields includes spaces or any other characters that will be parsed by shell, the "attr<operator>val" needs to be quoted. If the operator is "!~", the "attr<operator>val" needs to be quoted using single quote.
 


\ **-z|-**\ **-stanza**\ 
 
 Indicates that the file being piped to the command is in stanza format.  See the xcatstanzafile man page for details on using xCAT stanza files.
 


\ **-u**\ 
 
 Fill in the attributes such as template file, pkglist file and otherpkglist file of osimage object based on the specified parameters. It will search "/install/custom/" directory first, and then "/opt/xcat/share/".
 The \ *provmethod*\  and \ *profile*\  must be specified. If \ *osvers*\  or \ *osarch*\  is not specified, the corresponding value of the management node will be used.
 
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
 
 To create a site definition.
 
 
 .. code-block:: perl
 
   mkdef -t site -o clustersite  installdir=/xcatinstall
 
 


2.
 
 To create a basic node definition.
 
 
 .. code-block:: perl
 
   mkdef -t node -o node01 groups="all,aix"
 
 


3.
 
 To re-create the current definition of "node01".
 
 
 .. code-block:: perl
 
   mkdef -f -t node -o node01  nodetype=osi groups="linux"
 
 
 (The group definitions are also created if they don't already exist.)
 


4.
 
 To create a set of different types of definitions based on information contained in a stanza file.
 
 
 .. code-block:: perl
 
   cat defstanzafile | mkdef -z
 
 


5.
 
 To create a group definition called LinuxNodes containing the nodes clstrn01 and clstrn02.
 
 
 .. code-block:: perl
 
   mkdef -t group -o LinuxNodes members="clstrn01,clstrn02"
 
 


6.
 
 To create a node definition for an FSP node using the attributes provided by the group fspnodes.
 
 
 .. code-block:: perl
 
   mkdef -t node fspn1 groups=fspnodes nodetype=fsp
 
 


7.
 
 To create node definitions for a set of node host names contained in the node range "node1,node2,node3"
 
 
 .. code-block:: perl
 
   mkdef -t node node1,node2,node3 power=hmc groups="all,aix"
 
 


8.
 
 To create a dynamic node group definition called HMCMgtNodes containing all the HMC managed nodes"
 
 
 .. code-block:: perl
 
   mkdef -t group -o HMCMgtNodes -d -w mgt==hmc -w cons==hmc
 
 


9.
 
 To create a dynamic node group definition called SLESNodes containing all the SLES nodes
 
 
 .. code-block:: perl
 
   mkdef -t group -o SLESNodes -d -w "os=~^sles[0-9]+$"
 
 


10.
 
 To create a entry (7.0) in the policy table for user admin1
 
 
 .. code-block:: perl
 
   mkdef -t policy -o 7.0 name=admin1 rule=allow
 
 


11.
 
 To create a node definition with nic attributes
 
 
 .. code-block:: perl
 
   mkdef -t node cn1 groups=all nicips.eth0="1.1.1.1|1.2.1.1" nicnetworks.eth0="net1|net2" nictypes.eth0="Ethernet"
 
 


12.
 
 To create an osimage definition and fill in attributes automatically.
 
 
 .. code-block:: perl
 
   mkdef redhat6img -u profile=compute provmethod=statelite
 
 


13.
 
 To create a PowerLE kvm node definition with the xCAT shipped template "ppc64lekvmguest-template".
 
 
 .. code-block:: perl
 
   mkdef -t node cn1 --template ppc64lekvmguest-template ip=1.1.1.1 mac=42:3d:0a:05:27:0b vmhost=1.1.0.1 vmnics=br0
 
 


14.
 
 To create a node definition from an existing node definition "cn1"
 
 
 .. code-block:: perl
 
   mkdef -t node cn2 --template cn1 ip=1.1.1.2 mac=42:3d:0a:05:27:0c
 
 



*****
FILES
*****


$XCATROOT/bin/mkdef

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


chdef(1)|chdef.1, lsdef(1)|lsdef.1, rmdef(1)|rmdef.1, xcatstanzafile(5)|xcatstanzafile.5

