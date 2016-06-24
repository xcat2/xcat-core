
##########
csm2xcat.1
##########

.. highlight:: perl


****
NAME
****


\ **csm2xcat**\  - Allows the migration of a CSM database to an xCAT database.


********
SYNOPSIS
********


\ **csm2xcat**\  [\ **-**\ **-dir**\  \ *path*\ ]

\ **csm2xcat**\  [\ **-h**\ ]


***********
DESCRIPTION
***********


The csm2xcat command must be run on the Management Server of the CSM system that you want to migrate to xCAT.  The commmand will build  two xCAT stanza files that can update the xCAT database with the chdef command.

Copy the csm2xcat command to the CSM Management Server.  Run the command, indicating where you want your stanza files saved with the \ **-**\ **-dir**\  parameter.  Check the stanza files to see if the information is what you want put in the xCAT database. Copy the two stanza files: node.stanza, device.stanza back to your xCAT Management node, and run the chdef command to input into the xCAT database.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-**\ **-dir**\           Path to the directory containing the stanza files.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To build xCAT stanza files, enter on the CSM Management Server:


.. code-block:: perl

  csm2xcat --dir /tmp/mydir


2. To put the data in the xCAT database on the xCAT Management Node:


.. code-block:: perl

  cat node.stanza | chdef -z
 
  cat device.stanza | chdef -z



*****
FILES
*****


/opt/xcat/share/xcat/tools/csm2xcat

$dir/conversion.log


********
SEE ALSO
********


chdef(1)|chdef.1

