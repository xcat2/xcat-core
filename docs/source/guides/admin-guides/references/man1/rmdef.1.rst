
#######
rmdef.1
#######

.. highlight:: perl


****
NAME
****


\ **rmdef**\  - Use this command to remove xCAT data object definitions.


********
SYNOPSIS
********


\ **rmdef**\  [\ **-h | -**\ **-help**\ ] [\ **-t**\  \ *object-types*\ ]

\ **rmdef**\  [\ **-V | -**\ **-verbose**\ ] [\ **-a | -**\ **-all**\ ] [\ **-t**\  \ *object-types*\ ] [\ **-o**\  \ *object-names*\ ]
[\ **-f | -**\ **-force**\ ] [\ *noderange*\ ]


***********
DESCRIPTION
***********


This command is used to remove xCAT object definitions that are stored in the xCAT database.


*******
OPTIONS
*******



\ **-a|-**\ **-all**\ 
 
 Clear the whole xCAT database. A backup of the xCAT definitions should be saved before using this option.  Once all the data is removed the xCAT daemon will no longer work. Most xCAT commands will fail. 
 In order to use xCAT commands again, you have two options.  You can restore your database from your backup by switching to bypass mode, and running the restorexCATdb command. 
 You switch to bypass mode by setting the XCATBYPASS environmant variable.  (ex. "export XCATBYPASS=yes") 
 A second option is to run xcatconfig -d.  This will restore the initial setup of the database as when xCAT was initially installed. 
 You can then restart xcatd and run xCAT commands.
 


\ **-f|-**\ **-force**\ 
 
 Use this with the all option as an extra indicator that ALL definitions are to be removed.
 


\ **-h|-**\ **-help**\ 
 
 Display a usage message.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on supported formats.
 


\ **-o**\  \ *object-names*\ 
 
 A set of comma delimited object names.
 


\ **-t**\  \ *object-types*\ 
 
 A set of comma delimited object types.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********



1. To remove a range of node definitions.
 
 
 .. code-block:: perl
 
   rmdef -t node node1-node4
 
 


2. To remove all node definitions for the nodes contained in the group bpcnodes.
 
 
 .. code-block:: perl
 
   rmdef -t node -o bpcnodes
 
 


3. To remove the group called bpcnodes.
 
 
 .. code-block:: perl
 
   rmdef -t group -o bpcnodes
 
 
 (This will also update the values of the "groups" attribute of the member nodes.)
 



*****
FILES
*****


$XCATROOT/bin/rmdef

(The XCATROOT environment variable is set when xCAT is installed. The
default value is "/opt/xcat".)


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mkdef(1)|mkdef.1, lsdef(1)|lsdef.1, chdef(1)|chdef.1, xcatstanzafile(5)|xcatstanzafile.5

