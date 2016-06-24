
##########
xcat2nim.1
##########

.. highlight:: perl


****
NAME
****


\ **xcat2nim**\  - Use this command to create and manage AIX NIM definitions based on xCAT node, group and network object definitions.


********
SYNOPSIS
********


\ **xcat2nim [-h|-**\ **-help]**\ 

\ **xcat2nim [-V|-**\ **-verbose] [-u|-**\ **-update] [-l|-**\ **-list] [-r|-**\ **-remove] [-f|-**\ **-force] [-t object-types] [-o**\  \ *object-names*\ ] \ **[-a|-**\ **-allobjects] [-p|-**\ **-primarySN] [-b|-**\ **-backupSN]**\  \ *[noderange] [attr=val [attr=val...]]*\ 


***********
DESCRIPTION
***********


The \ **xcat2nim**\  command uses xCAT node, group and network object definitions to create, update, list, or remove corresponding NIM definitions.

Before you create or update NIM definitions the xCAT definitions must be created and NIM must be configured.

The \ **xcat2nim**\  command uses xCAT database information, command line input, and default values to run the appropriate NIM commands.

The xCAT node, group and network definition names will correspond to the NIM machine, machine group and network definitions.

Note:  The length of a NIM object name must be no longer than 39 characters.

To create or update a NIM definition you must provide the names of the xCAT definitions to use. The default behavior is to create new NIM definitions but not apply updates to existing definitions. If you wish to update existing NIM definitions then you must use the "update" option.  If you wish to completely remove the old definition and re-create it you must use the "force" option.

The xCAT code uses the appropriate NIM commands to create the NIM definitions.  To create definitions the "nim -o define" operation is used. To update definitions the "nim -o change" operation is used.  If you wish to specify additional information to pass to the NIM commands you can use the "attr=val" support.  The attribute names must correspond to the attributes supported by the relevant NIM commands.  (For example. "netboot_kernel=mp")

If the object type you are creating is a node then the object names can be a noderange value.

If you are using xCAT service nodes the \ **xcat2nim**\  command will automatically determine the correct server for the node and create the NIM definitions on that server.

The \ **xcat2nim**\  command support for NIM networks is limited to creating and listing.

When creating network definitions the command will check to make sure the network definition (or it's equivalent) does not exist and then create the required NIM network, route and interface definitions.  In some cases the equivalent network definition may exist using a different name.  In this case a new definition WILL NOT be created.

To list the NIM definitions that were created you must specify the "list" option and the names of the xCAT objects that were used to create the NIM definitions.  The \ **xcat2nim**\  command will list the corresponding NIM machine, machine group or network definitions using the "lsnim -l" command.

To remove NIM definitions you must specify the "remove" option and the names of the xCAT objects that were used to create the NIM definitions.

The remove("-r"), force("-f") and update("-u") options are not supported for NIM network definitions.


*******
OPTIONS
*******


\ **-a|-**\ **-all**\              The list of objects will include all xCAT node, group and network objects.

\ *attr=val [attr=val ...]*\   Specifies one or more "attribute equals value" pairs, separated by spaces. Attr=val pairs must be specified last on the command line.  The attribute names must correspond to the attributes supported by the relevant NIM commands.  When providing attr=val pairs on the command line you must not specify more than one object type.

\ **-b|-**\ **-backupSN**\        When using backup service nodes only update the backup.  The default is to update both the primary and backup service nodes.

\ **-f|-**\ **-force**\    	 The force option will remove the existing NIM definition and create a new one.

\ **-h|-**\ **-help**\             Display the usage message.

\ **-l|-**\ **-list**\ 		 List NIM definitions corresponding to xCAT definitions.

\ **-o**\  \ *object-names*\     A set of comma delimited xCAT object names. Objects must be of type node, group, or network.

\ **-p|-**\ **-primarySN**\         When using backup service nodes only update the primary.  The default is to update both the primary and backup service nodes.

\ **-r|-**\ **-remove**\          Remove NIM definitions corresponding to xCAT definitions.

\ **-t**\  \ *object-types*\        A set of comma delimited xCAT object types. Supported types include: node, group, and network.

Note: If the object type is "group", it means that the \ **xcat2nim**\  command will operate on a NIM machine group definition corresponding to the xCAT node group definition. Before creating a NIM machine group, all the NIM client nodes definition must have been created.

\ **-u|-**\ **-update**\         Update existing NIM definitions based on xCAT definitions.

\ **-V|-**\ **-verbose**\        Verbose mode.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To create a NIM machine definition corresponding to the xCAT node "clstrn01".


.. code-block:: perl

  xcat2nim -t node -o clstrn01


2. To create NIM machine definitions for all xCAT node definitions.


.. code-block:: perl

  xcat2nim -t node


3. Update all the NIM machine definitions for the nodes contained in the xCAT "compute" node group and specify attribute values that will be applied to each definition.


.. code-block:: perl

  xcat2nim -u -t node -o compute netboot_kernel=mp cable_type="N/A"


4. To create a NIM machine group definition corresponding to the xCAT group "compute".


.. code-block:: perl

  xcat2nim -t group -o compute


5. To create NIM network definitions corresponding to the xCAT "clstr_net" an "publc_net" network definitions.  Also display verbose output.


.. code-block:: perl

  xcat2nim -V -t network -o "clstr_net,publc_net"


6. To list the NIM definition for node clstrn02.


.. code-block:: perl

  xcat2nim -l -t node clstrn02


7. To re-create a NIM machine definiton and display verbose output.


.. code-block:: perl

  xcat2nim -V -t node -f clstrn05


8. To remove the NIM definition for the group "AIXnodes".


.. code-block:: perl

  xcat2nim -t group -r -o AIXnodes


9. To list the NIM "clstr_net" definition.


.. code-block:: perl

  xcat2nim -l -t network -o clstr_net



*****
FILES
*****


$XCATROOT/bin/xcat2nim


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mkdef(1)|mkdef.1

