
###########
nodechmac.1
###########

.. highlight:: perl


****
NAME
****


\ **nodechmac**\  - Updates the MAC address for a node.


********
SYNOPSIS
********


\ **nodechmac**\  [\ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]

\ **nodechmac**\  \ *node-name*\  \ **mac=**\ \ *mac-address*\ 


***********
DESCRIPTION
***********


The \ **nodechmac**\  command changes the MAC address for provisioned node’s network interface.

You can use this command to keep an existing node configuration. For example, if an existing node has hardware problems, the replacement node can use the old configurations. By using the nodechmac command, the node name and network settings of the old node can be used by the new node.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.

\ *node-name*\ 

Specifies the name of the node you want to update, where <node-name> is the node that is updated.

\ **mac=**\ \ *mac-address*\ 

Sets the new MAC address for the NIC used by the provisioning node, where <mac-address> is the NICs new MAC address.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********


You can update the MAC address for a node, by using the following command:


.. code-block:: perl

  nodechmac compute-000 mac=2F:3C:88:98:7E:01



********
SEE ALSO
********


