
###########
xpbsnodes.1
###########

.. highlight:: perl


****
NAME
****


\ **xpbsnodes**\  - PBS pbsnodes front-end for a noderange.


********
SYNOPSIS
********


\ **xpbsnodes**\  [{\ *noderange*\ }] [{\ **offline | clear | stat | state**\ }]

\ **xpbsnodes**\  [\ **-h | -**\ **-help**\ ] [\ **-v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


\ **xpbsnodes**\  is a front-end to PBS pbsnode but uses xCAT's noderange to specify nodes.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\                Display usage message.

\ **-v|-**\ **-version**\                Command Version.

\ **offline|off**\       Take nodes offline.

\ **clear|online|on**\   Take nodes online.

\ **stat|state**\        Display PBS node state.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To display status of all PBS nodes, enter:


.. code-block:: perl

  xpbsnodes all stat



*****
FILES
*****


/opt/torque/x86_64/bin/xpbsnodes


********
SEE ALSO
********


noderange(3)|noderange.3

