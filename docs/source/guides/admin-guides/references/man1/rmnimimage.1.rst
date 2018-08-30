
############
rmnimimage.1
############

.. highlight:: perl


****
NAME
****


\ **rmnimimage**\  - Use this xCAT command to remove NIM resources specified in an xCAT osimage definition.


********
SYNOPSIS
********


\ **rmnimimage [-h|-**\ **-help]**\ 

\ **rmnimimage [-V|-**\ **-verbose] [-f|-**\ **-force] [-d|-**\ **-delete] [-x|-**\ **-xcatdef] [-M|-**\ **-managementnode] [-s**\  \ *servicenoderange*\ ] \ *osimage_name*\ 


***********
DESCRIPTION
***********


Use this xCAT command to remove the AIX resources specified in an xCAT osimage definition.

To list the contents of the xCAT osimage definition use the xCAT \ **lsdef**\  command ("lsdef -t osimage -l -o <osimage_name>"). \ **Before running the rmnimimage command you should be absolutely certain that you really want to remove the NIM resources specified in the xCAT osimage definition!**\ 

The default behavior of this command is to remove all the NIM resources, except the lpp_source, on the xCAT management node in addition to the resources that were replicated on any xCAT service nodes.

This command may also be used to clean up individual xCAT service nodes and remove the xCAT osimage definitions.

The "nim -o remove" operation is used to remove the NIM resource definitions.  If you wish to completely remove all the files and directories (left behind by the NIM command) you must specify the "-d" option when you run \ **rmnimimage**\ .  The "-d" option will also remove the lpp_source resource.

If you wish to remove the NIM resource from one or more xCAT service nodes without removing the resources from the management node you can use the "-s <servicenoderange>" option.   In this case the NIM resources specified in the xCAT osimage definition will be removed from the service nodes ONLY.  The NIM resources on the management node will not be removed.

If you wish to remove NIM resources on the management node only, you can specify the "-M" option.

If you wish to also remove the xCAT osimage definition you must specify the "-x" option.

This command will not remove NIM resources if they are currently being used in another xCAT osimage definition.  To see which resources are common between osimages you can specify the "-V" option.  You can override this check by specifying the "-f" option.

This command will not remove NIM resources if they are currently allocated.  You must deallocate the resources before they can be removed.   See the \ **xcat2nim**\  and \ **rmdsklsnode**\  commands for information on how to deallocate and remove NIM machine definitions for standalone and diskless nodes.

See the AIX NIM documentation for additional details on how to deallocate and remove unwanted NIM objects.


*******
OPTIONS
*******



\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-d|-**\ **-delete**\ 
 
 Delete any files or directories that were left after the "nim -o remove" command was run. This option will also remove the lpp_source resouce and all files contained in the lpp_source directories. When this command completes all definitions and files will be completely erased so use with caution!
 


\ **-f|-**\ **-force**\ 
 
 Override the check for shared resources when removing an xCAT osimage.
 


\ **-M|-**\ **-managementnode**\ 
 
 Remove NIM resources from the xCAT management node only.
 


\ **-s**\  \ *servicenoderange*\ 
 
 Remove the NIM resources on these xCAT service nodes only.  Do not remove the NIM resources from the xCAT management node.
 


\ *osimage_name*\ 
 
 The name of the xCAT osimage definition.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode. This option will display the underlying NIM commands that are being called.
 


\ **-x|-**\ **-xcatdef**\ 
 
 Remove the xCAT osimage definition.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********


1) Remove all NIM resources specified in the xCAT "61image" definition.


.. code-block:: perl

  rmnimimage 61image


The "nim -o remove" operation will be used to remove the NIM resource definitions on the management node as well as any service nodes where the resource has been replicated.   This NIM operation does not completely remove all files and directories associated with the NIM resources.

2) Remove all the NIM resources specified by the xCAT "61rte" osimage definition.  Delete ALL files and directories associated with the NIM resources. This will also remove the lpp_source resource.


.. code-block:: perl

  rmnimimage -d 61rte


3) Remove all the NIM resources specified by the xCAT "614img" osimage definition and also remove the xCAT definition.


.. code-block:: perl

  rmnimimage -x -d 614img


Note: When this command completes all definitions and files will be completely erased, so use with caution!

4) Remove the NIM resources specified in the "614dskls" osimage definition on the xcatsn1 and xcatsn2 service nodes.  Delete all files or directories associated with the NIM resources.


.. code-block:: perl

  rmnimimage -d -s xcatsn1,xcatsn2 614dskls


5) Remove the NIM resources specified in the "614old" osimage definition on the xCAT management node only.


.. code-block:: perl

  rmnimimage -M -d 614old



*****
FILES
*****


/opt/xcat/bin/rmnimimage


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mknimimage(1)|mknimimage.1

