
#########
rbeacon.1
#########

.. highlight:: perl


********
SYNOPSIS
********


\ **rbeacon**\  \ *noderange*\  {\ **on | blink | off | stat**\ }

\ **rbeacon**\  [\ **-h | -**\ **-help**\ ]

\ **rbeacon**\  {\ **-v | -**\ **-version**\ }


***********
DESCRIPTION
***********


\ **rbeacon**\  Turns beacon (a light on the front of the physical server) on/off/blink or gives status of a node or noderange.


********
EXAMPLES
********



.. code-block:: perl

    rbeacon 1,3 off
    rbeacon 14-56,70-203 on
    rbeacon 1,3,14-56,70-203 blink
    rbeacon all,-129-256 stat



********
SEE ALSO
********


noderange(3)|noderange.3, rpower(1)|rpower.1

