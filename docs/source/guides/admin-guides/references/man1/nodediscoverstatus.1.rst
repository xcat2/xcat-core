
####################
nodediscoverstatus.1
####################

.. highlight:: perl


****
NAME
****


\ **nodediscoverstatus**\  - gets the node discovery process status


********
SYNOPSIS
********


\ **nodediscoverstatus**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **nodediscoverstatus**\  command detects if the sequential or profile node discovery process is currently running, i.e. \ **nodediscoverstart**\ 
has been run, but \ **nodediscoverstop**\  has not.


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


To determine if there are some nodes discovered and the discovered nodes' status, enter the following command:


.. code-block:: perl

  nodediscoverstatus



********
SEE ALSO
********


nodediscoverstart(1)|nodediscoverstart.1, nodediscoverls(1)|nodediscoverls.1, nodediscoverstatus(1)|nodediscoverstop.1

