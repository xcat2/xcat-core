
############
pushinitrd.1
############

.. highlight:: perl


****
NAME
****


\ **pushinitrd**\  - queries your SoftLayer account and gets attributes for each server.


********
SYNOPSIS
********


\ **pushinitrd**\  [\ **-v | -**\ **-verbose**\ ]  [\ **-w**\  \ *waittime*\ ] [\ *noderange*\ ]

\ **pushinitrd**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The \ **pushinitrd**\  command copies the initrd, kernel, params, and static IP info to nodes, so they can be net installed
even across vlans (w/o setting up pxe/dhcp broadcast relay).  This assumes a working
OS is on the nodes.  Before running this command, you must run nodeset for these nodes.
All of the nodes given to one invocation of \ **pushinitrd**\  must be using the same osimage.

Before using this command, if will be most convenient if you exchange the ssh keys using:


.. code-block:: perl

    xdsh <noderange> -K



*******
OPTIONS
*******



\ **-w**\  \ *waittime*\ 
 
 The number of seconds the initrd should wait before trying to communicate over the network.
 The default is 75.  This translates into the netwait kernel parameter and is usually needed
 in a SoftLayer environment because it can take a while for a NIC to be active after changing state.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1.
 
 Configure nodes for net installing in a SoftLayer environment:
 
 
 .. code-block:: perl
 
   pushinitrd <noderange>
 
 



*****
FILES
*****


/opt/xcat/bin/pushinitrd


********
SEE ALSO
********


getslnodes(1)|getslnodes.1

