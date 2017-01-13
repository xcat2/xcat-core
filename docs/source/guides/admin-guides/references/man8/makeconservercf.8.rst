
#################
makeconservercf.8
#################

.. highlight:: perl


****
NAME
****


\ **makeconservercf**\  - creates the conserver configuration file from info in the xCAT database


********
SYNOPSIS
********


\ **makeconservercf**\  [\ **-V|-**\ **-verbose**\ ] [\ **-d|-**\ **-delete**\ ] [\ *noderange*\ ]

\ **makeconservercf**\  [\ **-V|-**\ **-verbose**\ ] [\ **-l|-**\ **-local**\ ] [\ *noderange*\ ]

\ **makeconservercf**\  [\ **-V|-**\ **-verbose**\ ] [\ **-c|-**\ **-conserver**\ ] [\ *noderange*\ ]

\ **makeconservercf**\  [\ **-V|-**\ **-verbose**\ ] \ *noderange*\  [\ **-t|-**\ **-trust**\ ] \ *hosts*\ 

\ **makeconservercf**\  [\ **-h|-**\ **-help|-v|-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **makeconservercf**\  command will write out the /etc/conserver.cf, using information from the nodehm table
and related tables (e.g. mp, ipmi, ppc).  Normally, \ **makeconservercf**\  will write all nodes to the /etc/conserver.cf
file.  If a \ *noderange*\  is specified, it will write only those nodes to the file.  In either case, if a node
does not have nodehm.cons set, it will not be written to the file.

If \ **-d**\  is specified, \ **makeconservercf**\  will remove specified nodes from /etc/conserver.cf file. If \ *noderange*\  is not specified, all xCAT nodes will be removed from /etc/conserver.cf file.

In the case of a hierarchical cluster (i.e. one with service nodes) \ **makeconservercf**\  will determine
which nodes will have their consoles accessed from the management node and which from a service node
(based on the nodehm.conserver attribute).  The /etc/conserver.cf file will be created accordingly on
all relevant management/service nodes.  If \ **-l**\  is specified, it will only create the local file.


*******
OPTIONS
*******



\ **-d|-**\ **-delete**\ 
 
 Delete rather than add or refresh the nodes specified as a noderange.
 


\ **-c|-**\ **-conserver**\ 
 
 Only set up the conserver on the conserver host. If no conserver host
 is set for nodes, the conserver gets set up only on the management node.
 


\ **-l|-**\ **-local**\ 
 
 Only run \ **makeconservercf**\  locally and create the local /etc/conserver.cf.  The default is to also
 run it on all service nodes, if there are any.
 


\ **-t|-**\ **-trust**\  \ *hosts*\ 
 
 Add additional trusted hosts into /etc/conserver.cf. The \ *hosts*\  are comma separated list of
 ip addresses or host names.
 


\ **-v|-**\ **-version**\ 
 
 Display version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1. To create conserver configuration for all the nodes.
 
 
 .. code-block:: perl
 
   makeconservercf
 
 


2. To create conserver configuration for nodes node01-node10.
 
 
 .. code-block:: perl
 
   makeconservercf node01-node10
 
 


3. To remove conserver configuration for node01.
 
 
 .. code-block:: perl
 
   makeconservercf -d node01
 
 



********
SEE ALSO
********


rcons(1)|rcons.1

