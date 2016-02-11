
###############
nodeaddunmged.1
###############

.. highlight:: perl


****
NAME
****


\ **nodeaddunmged**\  - Create a unmanaged node.


********
SYNOPSIS
********


\ **nodeaddunmged**\  [\ **-h**\ | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]

\ **nodeaddunmged hostname=**\ \ *node-name*\  \ **ip=**\ \ *ip-address*\ 


***********
DESCRIPTION
***********


The \ **nodeaddunmged**\  command adds an unmanaged node to the __Unmanaged group. You can specify the node name and IP address of the node.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.

\ **hostname=**\ \ *node-name*\ 

Sets the name of the new unmanaged node, where <node-name> is the name of the node.

\ **ip=**\ \ *ip-address*\ 

Sets the IP address of the unmanaged node, where \ *ip-address*\  is the IP address of the new node in the form xxx.xxx.xxx.xxx


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********


To add an unmanaged node, use the following command:


.. code-block:: perl

  nodeaddunmged hostname=unmanaged01 ip=192.168.1.100



********
SEE ALSO
********


