
###########
nodepurge.1
###########

.. highlight:: perl


****
NAME
****


\ **nodepurge**\  - Removes nodes.


********
SYNOPSIS
********


\ **nodepurge [-h| -**\ **-help | -v | -**\ **-version]**\ 

\ **nodepurge**\  \ *noderange*\ 


***********
DESCRIPTION
***********


The \ **nodepurge**\  automatically removes all nodes from the database and any related configurations used by the node.

After the nodes are removed, the configuration files related to these nodes are automatically updated, including the following files: /etc/hosts, DNS, DHCP. Any kits that are used by the nodes are triggered to automatically update kit configuration and services.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\ 

Display usage message.

\ **-v|-**\ **-version**\ 

Command Version

\ *noderange*\ 

The nodes to be removed.


************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********


To remove nodes compute-000 and compute-001, use the following command:


.. code-block:: perl

  nodepurge compute-000,compute-001



********
SEE ALSO
********


nodeimport(1)|nodeimport.1, nodechprofile(1)|nodechprofile.1, noderefresh(1)|noderefresh.1, noderange(3)|noderange.3

