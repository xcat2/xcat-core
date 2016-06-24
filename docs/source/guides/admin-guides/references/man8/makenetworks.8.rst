
##############
makenetworks.8
##############

.. highlight:: perl


****
NAME
****


\ **makenetworks**\  - Gather cluster network information and add it to the xCAT database.


********
SYNOPSIS
********


\ **makenetworks**\  [\ **-h**\  | \ **-**\ **-help**\  ]

\ **makenetworks**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **makenetworks**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-d | -**\ **-display**\ ]


***********
DESCRIPTION
***********


The \ **makenetworks**\  command can be used to gather network information from an xCAT cluster environment and create corresponding network definitions in the xCAT database.

Every network that will be used to install a cluster node must be defined in the xCAT database.

The default behavior is to gather network information from the managment node, and any configured xCAT service nodes, and automatically save this information in the xCAT database.

You can use the "-d" option to display the network information without writing it to the database.

You can also redirect the output to a file that can be used with the xCAT \ **mkdef**\  command to define the networks.

For example:


.. code-block:: perl

 	makenetworks -d > mynetstanzas
 
 	cat mynetstanzas | mkdef -z


This features allows you to verify and modify the network information before writing it to the database.

When the network information is gathered a default value is created for the "netname" attribute.  This is done to make it possible to use the mkdef, chdef, lsdef, and rmdef commands to manage this data.

The default naming convention is to use a hyphen separated "net" and "mask" value with the "." replace by "_". (ex. "8_124_47_64-255_255_255_0")

You can also modify the xCAT "networks" database table directly using the xCAT \ **tabedit**\  command.


.. code-block:: perl

    	tabedit networks


Note: The \ **makenetworks**\  command is run automatically when xCAT is installed on a Linux management node.


*******
OPTIONS
*******


\ **-d|-**\ **-display**\        Display the network definitions but do not write to the definitions to the xCAT database. The output will be in stanza file format and can be redirected to a stanza file that can be used with \ **mkdef**\  or \ **chdef**\  commands to create or modify the network definitions.

\ **-h | -**\ **-help**\          Display usage message.

\ **-v | -**\ **-version**\       Command Version.

\ **-V |-**\ **-verbose**\        Verbose mode.


************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. Gather cluster network information and create xCAT network definitions.
 
 
 .. code-block:: perl
 
  	makenetworks
 
 


2. Display cluster network information but do not write the network definitions to the xCAT database.
 
 
 .. code-block:: perl
 
  	makenetworks -d
 
 
 The output would be one or more stanzas of information similar to the following. The line that ends with a colon is the value of the "netname" attribute and is the name of the network object to use with the lsdef, mkdef, chdef and rmdef commands.
 
 9_114_37_0-255_255_255_0:
     objtype=network
     gateway=9.114.37.254
     mask=255.255.255.0
     net=9.114.37.0
 



*****
FILES
*****


/opt/xcat/sbin/makenetworks


********
SEE ALSO
********


makedhcp(8)|makedhcp.8

