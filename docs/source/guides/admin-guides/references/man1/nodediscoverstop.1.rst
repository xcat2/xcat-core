
##################
nodediscoverstop.1
##################

.. highlight:: perl


****
NAME
****


\ **nodediscoverstop**\  - stops the node discovery process.


********
SYNOPSIS
********


\ **nodediscoverstop**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **nodediscoverstop**\  command stops the sequential or profile node discovery process.
Once this command has been run, newly discovered nodes will not be assigned node names
and attributes automatically via the sequential or profile discovery process.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********



.. code-block:: perl

  nodediscoverstop



********
SEE ALSO
********


nodediscoverstart(1)|nodediscoverstart.1, nodediscoverls(1)|nodediscoverls.1, nodediscoverstatus(1)|nodediscoverstatus.1

