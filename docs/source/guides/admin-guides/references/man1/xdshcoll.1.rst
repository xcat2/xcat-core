
##########
xdshcoll.1
##########

.. highlight:: perl


************
\ **NAME**\ 
************


\ **xdshcoll**\  - Formats and consolidates the output of the \ **xdsh,sinv**\  commands.


****************
\ **SYNOPSIS**\ 
****************


\ **xdshcoll**\ 


*******************
\ **DESCRIPTION**\ 
*******************


The  \ **xdshcoll**\  command formats and consolidates output from the \ **xdsh,sinv**\  command. The \ **xdshcoll**\ 
command takes, as input, lines in the following format:

host_name: line of output from remote command

The \ **xdshcoll**\  command formats the lines as follows and writes them  to
standard  output. Assume that the output from node3 and node4
is identical:


.. code-block:: perl

  ====================================
  node1
  ====================================
  .
  .
  lines from xdsh for node1 with hostnames stripped off
  .
  .
 
  ====================================
  node2
  ====================================
  .
  .
  lines from xdsh for node2 with hostnames stripped off
  .
  .
 
  ====================================
  node3, node4
  ====================================
  .
  .
  lines from xdsh for node 3 with hostnames stripped off
  .
  .



****************
\ **EXAMPLES**\ 
****************



1. To  display the results of a command issued on several nodes, in
the format used in the Description, enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2,node3 cat /etc/passwd> | B<xdshcoll
 
 



****************
\ **SEE ALSO**\ 
****************


xdshbak(1)|xdshbak.1

