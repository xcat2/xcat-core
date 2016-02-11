
################
nodediscoverls.1
################

.. highlight:: perl


****
NAME
****


\ **nodediscoverls**\  -  List the discovered nodes


********
SYNOPSIS
********


\ **nodediscoverls**\  [\ **-t seq | profile | switch | blade | manual | undef | all**\ ] [\ **-l**\ ]

\ **nodediscoverls**\  [\ **-u**\  \ *uuid*\ ] [\ **-l**\ ]

\ **nodediscoverls**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **nodediscoverls**\  command lists nodes that have recently been discovered.  If discovery
is currently in progress (i.e. \ **nodediscoverstart**\  has been run, but \ **nodediscoverstop**\  has not been),
then \ **nodediscoverls**\  will list the nodes that have been discovered so far in this session.
If discovery is not currently in progress, \ **nodediscoverls**\  will list all of the nodes that were
discovered in the last discovery session.

You can use the \ **-t**\  option to limit the output to just the nodes that were discovered in a
particular method of discovery.


*******
OPTIONS
*******



\ **-t seq|profile|switch|blade|manual|undef|all**\ 
 
 Display the nodes that have been discovered by the specified discovery method:
 
 
 \* \ **seq**\  - Sequential discovery (started via nodediscoverstart noderange=<noderange> ...).
 
 
 
 \* \ **profile**\  - Profile discovery (started via nodediscoverstart networkprofile=<network-profile> ...).
 
 
 
 \* \ **switch**\  - Switch-based discovery (used when the switch and switches tables are filled in).
 
 
 
 \* \ **blade**\  - Blade discovery (used for IBM Flex blades).
 
 
 
 \* \ **manual**\  - Manually discovery (used when defining node by nodediscoverdef command).
 
 
 
 \* \ **undef**\  - Display the nodes that were in the discovery pool, but for which xCAT has not yet received a discovery request.
 
 
 
 \* \ **all**\  - All discovered nodes.
 
 
 


\ **-l**\ 
 
 Display more detailed information about the discovered nodes.
 


\ **-u**\  \ *uuid*\ 
 
 Display the discovered node that has this uuid.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-v|-**\ **-version**\ 
 
 Command version.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occured.


********
EXAMPLES
********



1. Display the discovered nodes when sequential discovery is running:
 
 
 .. code-block:: perl
 
   nodediscoverls
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   UUID                                    NODE                METHOD         MTM       SERIAL
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB2    distest1            sequential     786310X   1052EF2
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB3    distest2            sequential     786310X   1052EF3
 
 


2. Display the nodes that were in the discovery pool, but for which xCAT has not yet received a discovery request:
 
 
 .. code-block:: perl
 
   nodediscoverls -t undef
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   UUID                                    NODE                METHOD         MTM       SERIAL
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB0    undef               undef          786310X   1052EF0
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB1    undef               undef          786310X   1052EF1
 
 


3. Display all the discovered nodes:
 
 
 .. code-block:: perl
 
   nodediscoverls -t all
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   UUID                                    NODE                METHOD         MTM       SERIAL
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB0    undef               undef          786310X   1052EF0
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB1    undef               undef          786310X   1052EF1
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB2    distest1            sequential     786310X   1052EF2
   51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB3    distest2            sequential     786310X   1052EF3
 
 


4. Display the discovered node whose uuid is \ **51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB2**\ , with detailed information:
 
 
 .. code-block:: perl
 
   nodediscoverls -u 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB2 -l
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Object uuid: 51E5F2D7-0D59-11E2-A7BC-3440B5BEDBB2
      node=distest1
      method=sequential
      discoverytime=03-31-2013 17:05:12
      arch=x86_64
      cpucount=32
      cputype=Intel(R) Xeon(R) CPU E5-2690 0 @ 2.90GHz
      memory=198460852
      mtm=786310X
      serial=1052EF2
      nicdriver=eth0!be2net,eth1!be2net
      nicipv4=eth0!10.0.0.212/8
      nichwaddr=eth0!34:40:B5:BE:DB:B0,eth1!34:40:B5:BE:DB:B4
      nicpci=eth0!0000:0c:00.0,eth1!0000:0c:00.1
      nicloc=eth0!Onboard Ethernet 1,eth1!Onboard Ethernet 2
      niconboard=eth0!1,eth1!2
      nicfirm=eth0!ServerEngines BE3 Controller,eth1!ServerEngines BE3 Controller
      switchname=eth0!c909f06sw01
      switchaddr=eth0!192.168.70.120
      switchdesc=eth0!IBM Flex System Fabric EN4093 10Gb Scalable Switch, flash image: version 7.2.6, boot image: version 7.2.6
      switchport=eth0!INTA2
 
 



********
SEE ALSO
********


nodediscoverstart(1)|nodediscoverstart.1, nodediscoverstatus(1)|nodediscoverstatus.1, nodediscoverstop(1)|nodediscoverstop.1, nodediscoverdef(1)|nodediscoverdef.1

