
###########
noderange.3
###########

.. highlight:: perl


****
Name
****


\ **noderange**\  - syntax for compactly expressing a list of node names


****************
\ **Synopsis**\ 
****************


\ *Examples:*\ 


.. code-block:: perl

  node1,node2,node8,node20,group1
 
  node14-node56,node70-node203,group1-group10
 
  node1,node2,node8,node20,node14-node56,node70-node203
 
  node[14-56]
 
  f[1-3]n[1-20]
 
  all,-node129-node256,-frame01-frame03
 
  /node.*
 
  ^/tmp/nodes
 
  node10+5
 
  10-15,-13
 
  group1@group2
 
  table.attribute<operator>value



*******************
\ **Description**\ 
*******************


\ **noderange**\  is a syntax that can be used in most xCAT commands to
conveniently specify a list of nodes.  The result is that the  command  will
be applied to a range of nodes, often in parallel.

\ **noderange**\  is a comma-separated list.  Each token (text between commas)
in the list can be any of the forms listed below:

Individual node or group:


.. code-block:: perl

  node01
  group1


A range of nodes or groups:


.. code-block:: perl

  node01-node10  (equivalent to: node01,node02,node03,...node10)
  node[01-10]    (same as above)
  node01:node10  (same as above)
  node[01:10]    (same as above)
  f[1-2]n[1-3]   (equivalent to: f1n1,f1n2,f1n3,f2n1,f2n2,f2n3)
  group1-group3  (equivalent to: group1,group2,group3)
  (all the permutations supported above for nodes are also supported for groups)


\ **nodeRange**\  tries to be intelligent about detecting padding, so
you can specify "node001-node200" and it will add the proper number of
zeroes to make all numbers 3 digits.

An incremented range of nodes:


.. code-block:: perl

  node10+3  (equivalent to: node10,node11,node12,node13)


A node shorthand range of nodes:


.. code-block:: perl

  10-20   (equivalent to: node10,node11,node12,...node20)
  10+3    (equivalent to: node10,node11,node12,node13)


Currently, the prefix that will be prepended for the above syntax is always "node".
Eventually, the prefix and optional suffix will be settable via the environment variables
XCAT_NODE_PREFIX and XCAT_NODE_SUFFIX, but currently this only works in bypass mode.

A regular expression match of nodes or groups:


.. code-block:: perl

  /node[345].*   (will match any nodes that start with node3, node4, or node5)
  /group[12].*   (will match any groups that start with group1 or group2)


The path of a file containing noderanges of nodes or groups:


.. code-block:: perl

  ^/tmp/nodelist


where /tmp/nodelist can contain entries like:


.. code-block:: perl

  #my node list (this line ignored)
  ^/tmp/foo #ignored
  node01    #node comment
  node02
  node03
  node10-node20
  /group[456].*
  -node50


Node ranges can contain any combination:


.. code-block:: perl

  node01-node30,node40,^/tmp/nodes,/node[13].*,2-10,node50+5


Any individual \ **noderange**\  may be prefixed with an exclusion operator
(default -) with the exception of the file operator (default ^).  This will cause
that individual noderange to be subtracted from the total resulting list of nodes.

The intersection operator @ calculates the intersection of the left and
right sides:


.. code-block:: perl

  group1@group2   (will result in the list of nodes that group1 and group2 have in common)


Any  combination  or  multiple  combinations of inclusive and exclusive
ranges of nodes and groups is legal.  There is no precedence implied in
the  order  of  the  arguments.   Exclusive ranges have precedence over
inclusive.  Parentheses can be used to explicitly specify precendence of any operators.

Nodes have precedence over groups.  If a node range match is made then
no group range match will be attempted.

All node and group names are validated against the nodelist table.  Invalid names
are ignored and return nothing.

\ **xCAT Node Name Format**\ 
=============================


Throughout this man page the term \ **xCAT Node Name Format**\  is used.
\ **xCAT Node Name Format**\  is defined by the following regex:


.. code-block:: perl

  ^([A-Za-z-]+)([0-9]+)(([A-Za-z-]+[A-Za-z0-9-]*)*)


In  plain  English,  a  node or group name is in \ **xCAT Node Name Format**\  if starting
from the begining there are:


\* one or more alpha characters  of  any  case and  any  number  of "-" in any combination



\* followed by one or more numbers



\* then optionally followed by one alpha character of any case  or "-"



\* followed by any combination of case mixed alphanumerics and "-"



\ **noderange**\  supports node/group names in \ *any*\  format.  \ **xCAT Node Name Format**\  is
\ **not**\  required, however some node range methods used to determine range
will not be used for non-conformant names.

Example of \ **xCAT Node Name Format**\  node/group names:


.. code-block:: perl

  NODENAME           PREFIX      NUMBER   SUFFIX
  node1              node        1
  node001            node        001
  node-001           node-       001
  node-foo-001-bar   node-foo-   001      -bar
  node-foo-1bar      node-foo-   1        bar
  foo1bar2           foo         1        bar2
  rack01unit34       rack        01       unit34
  unit34rack01       unit        34       rack01
  pos0134            pos         0134




****************
\ **Examples**\ 
****************



1.
 
 Generates a list of all nodes (assuming all is a group) listed in the
 \ **nodelist**\  table less node5 through node10:
 
 
 .. code-block:: perl
 
   all,-node5-node10
 
 


2.
 
 Generates  a  list  of  nodes 1 through 10 less nodes 3,4,5.  Note that
 node4 is listed twice, first in the range and then at the end.  Because
 exclusion has precedence node4 will be excluded.
 
 
 .. code-block:: perl
 
   node1-node10,-node3-node5,node4
 
 


3.
 
 Generates a list of nodes 1 through 10 less nodes 3 and 5.
 
 
 .. code-block:: perl
 
   node1-node10,-node3,-node5
 
 


4.
 
 Generates  a  list  of  all  (assuming  \`all'  is a group) nodes in the
 \ **nodelist**\  table less 17 through 32.
 
 
 .. code-block:: perl
 
   -node17-node32,all
 
 


5.
 
 Generates a list of nodes 1 through 128, and user nodes 1 through 4.
 
 
 .. code-block:: perl
 
   node1-node128,user1-user4
 
 


6.
 
 Generates a list of all nodes (assuming \`all' is a group),  less  nodes
 in  groups rack1 through rack3 (assuming groups rack1, rack2, and rack3
 are defined), less nodes 100 through 200, less  nodes  in  the  storage
 group.  Note that node150 is listed but is excluded.
 
 
 .. code-block:: perl
 
   all,-rack1-rack3,-node100-node200,node150,-storage
 
 


7.
 
 Generates  a  list of nodes matching the regex \ *node[23].\\**\ .  That is all
 nodes that start with node2 or node3 and end in  anything  or  nothing.
 E.g. node2, node3, node20, node30, node21234 all match.
 
 
 .. code-block:: perl
 
   /node[23].*
 
 


8.
 
 Generates  a  list of nodes which have the value hmc in the nodehm.cons 
 attribute.
 
 
 .. code-block:: perl
 
   nodehm.cons==hmc
  
   nodehm.cons=~hmc
 
 


9.
 
 Generate a list of nodes in the 1st two frames:
 
 
 .. code-block:: perl
 
   f[1-2]n[1-42]
 
 



****************
\ **SEE ALSO**\ 
****************


nodels(1)|nodels.1

