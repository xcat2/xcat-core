
#########
xdshbak.1
#########

.. highlight:: perl


****
NAME
****


\ **xdshbak**\  - Formats the output of the \ **xdsh**\  command.


****************
\ **SYNOPSIS**\ 
****************


\ **xdshbak**\  [\ **-c**\  | \ **-x**\  [ \ **-b**\  ] | \ **-h**\  | \ **-q**\ ]


***********
DESCRIPTION
***********


The  \ **xdshbak**\   command formats output from the \ **xdsh**\  command. The \ **xdshbak**\ 
command takes, as input, lines in the following format:


.. code-block:: perl

  host_name: line of output from remote command


The \ **xdshbak**\  command formats the lines as follows  and  writes  them  to
standard  output. Assume that the output from node3 and node4
is identical, and the \ **-c**\  (collapse) flag was specified:


.. code-block:: perl

  HOSTS --------------------------------------------------------
  node1
  --------------------------------------------------------------
  .
  .
  lines from xdsh for node1 with hostnames stripped off
  .
  .
  HOSTS --------------------------------------------------------
  node2
  --------------------------------------------------------------
  .
  .
  lines from xdsh for node2 with hostnames stripped off
  .
  .
  HOSTS --------------------------------------------------------
  node3, node4
  --------------------------------------------------------------
  .
  .
  lines from xdsh for node 3 with hostnames stripped off
  .
  .


When output is displayed from more than one node in collapsed form, the
host  names are displayed alphabetically. When output is not collapsed,
output is displayed sorted alphabetically by host name.

If the \ **-q**\  quiet flag is not set then  \ **xdshbak**\ 
command writes "." for each 1000 lines of output processed (to show progress),
since it won't display the output until it has processed all of it.

If the \ **-x**\  flag is specified, the extra header lines that xdshbak normally
displays for each node will be omitted, and the hostname at the beginning
of each line is not stripped off, but \ **xdshbak**\   still sorts
the output by hostname for easier viewing:


.. code-block:: perl

  node1: lines from xdsh for node1
  .
  .
  node2: lines from xdsh for node2
  .
  .


If the \ **-b**\  flag is specified in addition to \ **-x**\ , the hostname at the beginning
of each line is stripped.

Standard Error
==============


When the \ **xdshbak**\  filter is used and standard error messages are generated,
all error messages on standard error appear before all standard
output messages. This is true with and without the \ **-c**\  flag.



*******
OPTIONS
*******



\ **-b**\ 
 
 Strip the host prefix from the beginning of the lines. This only
 works with the \ **-x**\  option.
 


\ **-c**\ 
 
 If the output from multiple nodes is identical it will be collapsed
 and displayed only once.
 


\ **-x**\ 
 
 Omit the extra header lines that xdshbak normally displays for
 each node.  This provides
 more  compact  output,  but  xdshbak still sorts the output by
 node name for easier viewing.
 This option should not be used with \ **-c**\ .
 


\ **-h**\ 
 
 Displays usage information.
 


\ **-q**\ 
 
 Quiet mode, do not display "." for each 1000 lines of output.
 



****************
\ **EXAMPLES**\ 
****************



1. To  display the results of a command issued on several nodes, in
the format used in the Description, enter:
 
 
 .. code-block:: perl
 
   xdsh node1,node2,node3 cat /etc/passwd | xdshbak
 
 


2.
 
 To display the results of a command issued on several nodes with
 identical output displayed only once, enter:
 
 
 .. code-block:: perl
 
   xdsh host1,host2,host3 pwd | xdshbak -c
 
 


3. To display the results of a command issued on several nodes with
compact output and be sorted alphabetically by host name, enter:
 
 
 .. code-block:: perl
 
   xdsh host1,host2,host3 date | xdshbak -x
 
 



****************
\ **SEE ALSO**\ 
****************


xdsh(1)|xdsh.1, xcoll(1)|xcoll.1

