
#############
noderefresh.1
#############

.. highlight:: perl


****
NAME
****


\ **noderefresh**\  - Update nodes configurations by running associated kit plugins.


********
SYNOPSIS
********


\ **noderefresh [-h| -**\ **-help | -v | -**\ **-version]**\ 

\ **noderefresh**\  \ *noderange*\ 


***********
DESCRIPTION
***********


The \ **noderefresh**\  command will update nodes settings, it will call all associated kit plug-in configurations and also services


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version.

\ *noderange*\ 

The nodes to be updated.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********



.. code-block:: perl

  noderefresh compute-000,compute-001



********
SEE ALSO
********


nodeimport(1)|nodeimport.1, nodechprofile(1)|nodechprofile.1, nodepurge(1)|nodepurge.1, noderange(3)|noderange.3

