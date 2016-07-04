
#######
lsdef.1
#######

.. highlight:: perl


****
NAME
****


\ **lsdef**\  - Use this command to list xCAT data object definitions.


********
SYNOPSIS
********


\ **lsdef**\  [\ **-h | -**\ **-help**\ ] [\ **-t**\  \ *object-types*\ ] [\ **-i**\  \ *attr-list*\ ]

\ **lsdef**\  [\ **-V | -**\ **-verbose**\ ] [\ **-l | -**\ **-long**\ ] [\ **-s | -**\ **-short**\ ] [\ **-a | -**\ **-all**\ ] [\ **-S**\ ] 
[\ **-t**\  \ *object-types*\ ] [\ **-o**\  \ *object-names*\ ] [\ **-z | -**\ **-stanza**\ ] [\ **-i**\  \ *attr-list*\ ]
[\ **-c | -**\ **-compress**\ ] [\ **-**\ **-osimage**\ ] [\ **-**\ **-nics**\ ] [[\ **-w**\  \ *attr*\ ==\ *val*\ ]
[\ **-w**\  \ *attr*\ =~\ *val*\ ] ...] [\ *noderange*\ ]

\ **lsdef**\  [\ **-l | -**\ **-long**\ ] [\ **-a | -**\ **-all**\ ] [\ **-t**\  \ *object-types*\ ] [\ **-z | -**\ **-stanza**\ ] 
[\ **-i**\  \ *attr-list*\ ] [\ **-**\ **-template**\  [\ *template-object-name*\ ]]


***********
DESCRIPTION
***********


This command is used to display xCAT object definitions which are stored
in the xCAT database and xCAT object definition templates shipped in xCAT.


*******
OPTIONS
*******



\ **-a|-**\ **-all**\ 
 
 Display all definitions.
 For performance consideration, the auditlog and eventlog objects will not be listed.
 To list auditlog or eventlog objects, use lsdef -t auditlog or lsdef -t eventlog instead.
 


\ **-c|-**\ **-compress**\ 
 
 Display information in compressed mode, each output line has format "<object name>: <data>".
 The output can be passed to command xcoll or xdshbak for formatted output. 
 The -c flag must be used with -i flag.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-i**\  \ *attr-list*\ 
 
 Comma separated list of attribute names to display.
 


\ **-l|-**\ **-long**\ 
 
 List the complete object definition.
 


\ **-s|-**\ **-short**\ 
 
 Only list the object names.
 


\ **-S**\ 
 
 List all the hidden nodes (FSP/BPA nodes) with other ones.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names.
 See the "noderange" man page for details on supported formats.
 


\ **-o**\  \ *object-names*\ 
 
 A set of comma delimited object names.
 


\ **-**\ **-template**\  [\ *template-object-name*\ ]
 
 Show the object definition templates \ *template-object-name*\   shipped in xCAT. If no \ *template-object-name*\  is specified, all the object definition templates of the specified type \ **-t**\  \ *object-types*\  will be listed. Use \ **-a|-**\ **-all**\  option to list all the object definition templates.
 


\ **-**\ **-osimage**\ 
 
 Show all the osimage information for the node.
 


\ **-**\ **-nics**\ 
 
 Show the nics configuration information for the node.
 


\ **-t**\  \ *object-types*\ 
 
 A set of comma delimited object types. Use the help option to get a list of valid objects.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-w**\  \ *attr==val*\  \ **-w**\  \ *attr=~val*\  ...
 
 Use one or multiple -w flags to specify the selection string that can be used to select objects. The operators ==, !=, =~ and !~ are available. Use the help option to get a list of valid attributes for each object type.
 
 Operator descriptions:
         ==        Select nodes where the attribute value is exactly this value.
         !=        Select nodes where the attribute value is not this specific value.
         =~        Select nodes where the attribute value matches this regular expression.
         !~        Select nodes where the attribute value does not match this regular expression.
 
 Note: if the "val" fields includes spaces or any other characters that will be parsed by shell, the "attr<operator>val" needs to be quoted. If the operator is "!~", the "attr<operator>val" needs to be quoted using single quote.
 


\ **-z|-**\ **-stanza**\ 
 
 Display output in stanza format. See the xcatstanzafile man page for details on using xCAT stanza files.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1.
 
 To display a description of all the valid attributes that could be used
 when defining an xCAT node.
 
 
 .. code-block:: perl
 
   lsdef -t node -h
 
 


2.
 
 To get a list of all the objects that have been defined.
 
 
 .. code-block:: perl
 
   lsdef
     OR
   lsdef -a
 
 


3.
 
 To get all the attributes of the node1
 
 
 .. code-block:: perl
 
   lsdef node1
     OR
   lsdef -t node node1
     OR
   lsdef -t node -o node1
 
 


4.
 
 To get the object name of node1 instead of all the attributes
 
 
 .. code-block:: perl
 
   lsdef -s node1
 
 


5.
 
 To get a list of all the network definitions.
 
 
 .. code-block:: perl
 
   lsdef -t network
 
 


6.
 
 To get a complete listing of all network definitions.
 
 
 .. code-block:: perl
 
   lsdef -l -t network
 
 


7.
 
 To list the whole xCAT database and write it to a stanza file. (backup database)
 
 
 .. code-block:: perl
 
   lsdef -a -l -z > mydbstanzafile
 
 


8.
 
 To list the MAC and install adapter name for each node.
 
 
 .. code-block:: perl
 
   lsdef -t node -i mac,installnic
 
 


9.
 
 To list an osimage definition named "aix53J".
 
 
 .. code-block:: perl
 
   lsdef -t osimage -l -o aix53J
 
 


10.
 
 To list all node definitions that have a status value of "booting".
 
 
 .. code-block:: perl
 
   lsdef -t node -w status==booting
 
 


11.
 
 To list all the attributes of the group "service".
 
 
 .. code-block:: perl
 
   lsdef -l -t group -o service
 
 


12.
 
 To list all the attributes of the nodes that are members of the group "service".
 
 
 .. code-block:: perl
 
   lsdef -t node -l service
 
 


13.
 
 To get a listing of object definitions that includes information about
 what xCAT database tables are used to store the data.
 
 
 .. code-block:: perl
 
   lsdef -V -l -t node -o node01
 
 


14.
 
 To list the hidden nodes that can't be seen with other flags.
 The hidden nodes are FSP/BPAs.
 
 
 .. code-block:: perl
 
   lsdef -S
 
 


15.
 
 To list the nodes status and use xcoll to format the output.
 
 
 .. code-block:: perl
 
   lsdef -t node -i status -c | xcoll
 
 


16.
 
 To display the description for some specific attributes that could be used
 when defining an xCAT node.
 
 
 .. code-block:: perl
 
   lsdef -t node -h -i profile,pprofile
 
 


17.
 
 To display the nics configuration information for node cn1.
 
 
 .. code-block:: perl
 
   lsdef cn1 --nics
 
 


18.
 
 To list all the object definition templates shipped in xCAT.
 
 
 .. code-block:: perl
 
   lsdef --template -a
 
 


19.
 
 To display the details of "node" object definition template "ppc64le-template" shipped in xCAT.
 
 
 .. code-block:: perl
 
   lsdef -t node --template ppc64le-template
 
 


20.
 
 To list all the "node" object definition templates shipped in xCAT.
 
 
 .. code-block:: perl
 
   lsdef -t node --template
 
 



*****
FILES
*****


/opt/xcat/bin/lsdef


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mkdef(1)|mkdef.1, chdef(1)|chdef.1, rmdef(1)|rmdef.1, xcatstanzafile(5)|xcatstanzafile.5

