
###############
updateSNimage.1
###############

.. highlight:: perl


****
NAME
****


\ **updateSNimage**\  - Adds the needed Service Node configuration files to the install image.


********
SYNOPSIS
********


\ **updateSNimage [-h | -**\ **-help ]**\ 

\ **updateSNimage [-v | -**\ **-version]**\ 

\ **updateSNimage**\  [\ **-n**\  \ *node*\ ] [\ **-p**\  \ *path*\ ]


***********
DESCRIPTION
***********


This command is used to add the Service Node configuration files to the install image. It will either copy them locally or scp them to a remote host.


*******
OPTIONS
*******


\ **-h |-**\ **-help**\             Display usage message.

\ **-v |-**\ **-version**\          Display xCAT version.

\ **-n |-**\ **-node**\             A remote host name or ip address that contains the install image to be updated.

\ **-p |-**\ **-path**\             Path to the install image.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To update the image on the local host.


.. code-block:: perl

  updateSNimage -p /install/netboot/fedora8/x86_64/test/rootimg


2. To update the image on a remote host.


.. code-block:: perl

  updateSNimage -n 9.112.45.6 -p /install/netboot/fedora8/x86_64/test/rootimg


