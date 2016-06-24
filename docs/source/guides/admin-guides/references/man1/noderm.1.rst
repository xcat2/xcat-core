
########
noderm.1
########

.. highlight:: perl


****
NAME
****


\ **noderm**\  -Removes the nodes in the noderange from all database table.


********
SYNOPSIS
********


\ **noderm [-h| -**\ **-help]**\ 

\ **noderm noderange**\ 


***********
DESCRIPTION
***********


The noderm command removes the nodes in the input node range.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\           Display usage message.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To remove the nodes in noderange node1-node4, enter:


.. code-block:: perl

  noderm node1-node4



*****
FILES
*****


/opt/xcat/bin/noderm


********
SEE ALSO
********


nodels(1)|nodels.1, nodeadd(8)|nodeadd.8, noderange(3)|noderange.3

