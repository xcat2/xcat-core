
########
lstree.1
########

.. highlight:: perl


****
NAME
****


\ **lstree**\  - Display the tree of service node hierarchy, hardware hierarchy, or VM hierarchy.


********
SYNOPSIS
********


\ **lstree**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **lstree**\  [\ **-s**\  | \ **-**\ **-servicenode**\ ] [\ **-H**\  | \ **-**\ **-hardwaremgmt**\ ] [\ **-v**\  | \ **-**\ **-virtualmachine**\ ] [\ *noderange*\ ]


***********
DESCRIPTION
***********


The \ **lstree**\  command can display the tree of service node hierarchy for the xCAT nodes which have service node defined or which are service nodes, display the tree of hardware hierarchy only for the physical objects, display the tree of VM hierarchy for the xCAT nodes which are virtual machines or which are the hosts of virtual machines. If a noderange is specified, only show the part of the hierarchy that involves those nodes. For ZVM, we only support to disply VM hierarchy. By default, lstree will show both the hardware hierarchy and the VM hierarchy for all the nodes.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-s|-**\ **- servicenode**\ 
 
 Show the tree of service node hierarchy.
 


\ **-H|-**\ **-hardwaremgmt**\ 
 
 Show the tree of hardware hierarchy.
 


\ **-**\ **-v|-**\ **-virtualmachine**\ 
 
 Show the tree of VM hierarchy.
 


\ *noderange*\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on additional supported formats.
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********



1. To display the tree of service node hierarchy for all the nodes.
 
 
 .. code-block:: perl
 
   lstree -s
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Service Node: mysn01
   |__mycn01
   |__mycn02
   |__mycn03
  
   Service Node: mysn02
   |__mycn11
   |__mycn12
   |__mycn13
   ......
 
 


2.
 
 To display the tree of service node hierarchy for service node "mysn01".
 
 
 .. code-block:: perl
 
   lstree -s mysn01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Service Node: mysn01
   |__mycn01
   |__mycn02
   |__mycn03
 
 


3.
 
 To display the tree of hardware hierarchy for all the nodes.
 
 
 .. code-block:: perl
 
   lstree -H
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   HMC: myhmc01
   |__Frame: myframe01
      |__CEC: mycec01
      |__CEC: mycec02
      ......
  
   Service Focal Point: myhmc02
   |__Frame: myframe01
      |__CEC: mycec01
      |__CEC: mycec02
      |__CEC: mycec03
      ......
  
   Management Module: mymm01
   |__Blade 1: js22n01
   |__Blade 2: js22n02
   |__Blade 3: js22n03
   ......
  
   BMC: 192.168.0.1
   |__Server: x3650n01
 
 


4. To display the tree of hardware hierarchy for HMC "myhmc01".
 
 
 .. code-block:: perl
 
   lstree -H myhmc01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   HMC: myhmc01
   |__Frame: myframe01
      |__CEC: mycec01
      |__CEC: mycec02
      ......
 
 


5. To display the tree of VM hierarchy for all the nodes.
 
 
 .. code-block:: perl
 
   lstree -v
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Server: hs22n01
   |__ hs22vm1
  
   Server: x3650n01
   |__ x3650n01kvm1
   |__ x3650n01kvm2
 
 


6. To display the tree of VM hierarchy for the node "x3650n01".
 
 
 .. code-block:: perl
 
   lstree -v x3650n01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   Server: x3650n01
   |__ x3650n01kvm1
   |__ x3650n01kvm2
 
 


7. To display both the hardware tree and VM tree for all nodes.
 
 
 .. code-block:: perl
 
   lstree
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   HMC: myhmc01
   |__Frame: myframe01
      |__CEC: mycec01
         |__LPAR 1: node01
         |__LPAR 2: node02
         |__LPAR 3: node03
         ......
      |__CEC: mycec02
         |__LPAR 1: node11
         |__LPAR 2: node12
         |__LPAR 3: node13
         ......
  
   Service Focal Point: myhmc02
   |__Frame: myframe01
      |__CEC: mycec01
         |__LPAR 1: node01
         |__LPAR 2: node02
         |__LPAR 3: node03
         ......
   |__Frame: myframe02
      |__CEC: mycec02
         |__LPAR 1: node21
         |__LPAR 2: node22
         |__LPAR 3: node23
         ......
  
   Management Module: mymm01
   |__Blade 1: hs22n01
      |__hs22n01vm1
      |__hs22n01vm2
   |__Blade 2: hs22n02
      |__hs22n02vm1
      |__hs22n02vm2
   ......
  
   BMC: 192.168.0.1
   |__Server: x3650n01
      |__ x3650n01kvm1
      |__ x3650n01kvm2
 
 



*****
FILES
*****


/opt/xcat/bin/lstree


********
SEE ALSO
********


noderange(3)|noderange.3, tabdump(8)|tabdump.8

