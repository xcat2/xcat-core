
#############
rmdsklsnode.1
#############

.. highlight:: perl


****
NAME
****


\ **rmdsklsnode**\  - Use this xCAT command to remove AIX/NIM diskless machine definitions.


********
SYNOPSIS
********


\ **rmdsklsnode [-h | -**\ **-help ]**\ 

\ **rmdsklsnode [-V|-**\ **-verbose] [-f|-**\ **-force] [-r|-**\ **-remdef] [-i**\  \ *image_name*\ ] \ **[-p|-**\ **-primarySN] [-b|-**\ **-backupSN]**\  \ *noderange*\ 


***********
DESCRIPTION
***********


Use this command to remove all NIM client machine definitions that were created for the specified xCAT nodes.

The xCAT node definitions will not be removed. Use the xCAT \ **rmdef**\  command to remove xCAT node definitions.

If you are using xCAT service nodes the \ **rmdsklsnode**\  command will automatically determine the correct server(s) for the node and remove the NIM definitions on that server(s).

If the node you are trying to remove is currently running the \ **rmdsklsnode**\  command will not remove the definitions.  You can use the "-f" option to shut down the node and remove the definition.

\ **Removing alternate NIM client definitions**\ 

If you used the "-n" option when you created the NIM client definitions with the \ **mkdsklsnode**\  command then the NIM client machine names would be a combination of the xCAT node name and the osimage name used to initialize the NIM machine. To remove these definitions you must provide the name of the osimage that was used using the "-i" option.

In most cases you would most likely want to remove the old client definitions without disturbing the nodes that you just booted with the new alternate client definition. The \ **rmdsklsnode -r**\  option can be used to remove the old alternate client defintions without stopping the running node.

However, if you have NIM dump resources assign to your nodes be aware that when the old NIM alternate client definitions are removed it will leave the nodes unable to produce a system dump.  This is a current limitation in the NIM support for alternate client definitions.  For this reason it is recommended that you wait to do this cleanup until right before you do your next upgrade.


*******
OPTIONS
*******



\ **-f |-**\ **-force**\ 
 
 Use the force option to stop and remove running nodes. This handles the situation where a NIM machine definition indicates that a node is still running even though it is not.
 


\ **-b |-**\ **-backupSN**\ 
 
 When using backup service nodes only update the backup.  The default is to updat
 e both the primary and backup service nodes.
 


\ **-h |-**\ **-help**\ 
 
 Display usage message.
 


\ **-i**\  \ *image_name*\ 
 
 The name of an xCAT image definition.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on additional supported formats.
 


\ **-p|-**\ **-primarySN**\ 
 
 When using backup service nodes only update the primary.  The default is to upda
 te both the primary and backup service nodes.
 


\ **-r|-**\ **-remdef**\ 
 
 Use this option to reset, deallocate, and remove NIM client definitions.  This option will not attempt to shut down running nodes. This option should be used when remove alternate NIM client definitions that were created using \ **mkdsklsnode -n**\ .
 


\ **-V |-**\ **-verbose**\ 
 
 Verbose mode.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********


1) Remove the NIM client definition for the xCAT node named "node01". Give verbose output.


.. code-block:: perl

  rmdsklsnode -V node01


2) Remove the NIM client definitions for all the xCAT nodes in the group "aixnodes". Attempt to shut down the nodes if they are running.


.. code-block:: perl

  rmdsklsnode -f aixnodes


3) Remove the NIM client machine definition for xCAT node "node02" that was created with the \ **mkdsklsnode -n**\  option and the image "AIXdskls". (i.e. NIM client machine name "node02_AIXdskls".)


.. code-block:: perl

  rmdsklsnode -i AIXdskls node02


This assume that node02 is not currently running.

4) Remove the old alternate client definition "node27_olddskls".


.. code-block:: perl

  rmdsklsnode -r -i olddskls node27


Assuming the node was booted using an new alternate NIM client definition then this will leave the node running.


*****
FILES
*****


/opt/xcat/bin/rmdsklsnode


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


mkdsklsnode(1)|mkdsklsnode.1

