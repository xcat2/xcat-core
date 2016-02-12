
#######
xcoll.1
#######

.. highlight:: perl


************
\ **NAME**\ 
************


\ **xcoll**\  - Formats and consolidates the output of the \ **psh**\ , \ **rinv**\  commands.


****************
\ **SYNOPSIS**\ 
****************


\ **xcoll**\  [\ **-n**\ ] [\ **-c**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


The  \ **xcoll**\  command formats and consolidates output from the \ **psh,rinv**\  command. The \ **xcoll**\ 
command takes, as input, lines in the following format:

groupname: line of output from remote command, will use group name, if defined

The \ **xcoll**\  command formats the lines as follows and writes them  to
standard  output. Assume that the output from node3 and node4
is identical:


.. code-block:: perl

  ====================================
  node1 or nodegroup name
  ====================================
  .
  .
  lines from psh for node1 with hostnames stripped off
  .
  .
 
  ====================================
  node2 or nodegroup name
  ====================================
  .
  .
  lines from psh for node2 with hostnames stripped off
  .
  .
 
  ====================================
  node3, node4 or nodegroup name
  ====================================
  .
  .
  lines from psh for node 3 with hostnames stripped off
  .
  .



***************
\ **OPTIONS**\ 
***************



\ **-c**\ 
 
 Display a total nodecount for each set of output.
 


\ **-n**\ 
 
 Display output as nodenames instead of groupnames.
 



****************
\ **EXAMPLES**\ 
****************



1. To  display the results of a command issued on several nodes, in
the format used in the Description, enter:
 
 
 .. code-block:: perl
 
   psh node1,node2,node3 cat /etc/passwd | xcoll
 
 



****************
\ **SEE ALSO**\ 
****************


psh(1)|psh.1, xdshbak(1)|xdshbak.1 ,xdshcoll(1)|xdshcoll.1

