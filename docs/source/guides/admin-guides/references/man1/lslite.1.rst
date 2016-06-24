
########
lslite.1
########

.. highlight:: perl


****
NAME
****


\ **lslite**\  - Display a summary of the statelite information.


********
SYNOPSIS
********


\ **lslite**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **lslite**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-i**\  \ *imagename*\ ] | [\ *noderange*\ ]


***********
DESCRIPTION
***********


The \ **lslite**\  command displays a summary of the statelite information that has been defined for a noderange or an image.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-i**\  \ *imagename*\ 
 
 The name of an existing xCAT osimage definition.
 


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



1.
 
 To list the statelite information for an xCAT node named "node01".
 
 
 .. code-block:: perl
 
   lslite node01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   >>>Node: node01
  
   Osimage: 61img
  
   Persistent directory (statelite table):
          xcatmn1:/statelite
  
   Litefiles (litefile table):
          tmpfs,rw      /etc/adjtime
          tmpfs,rw      /etc/lvm/.cache
          tmpfs,rw      /etc/mtab
          ........
  
   Litetree path (litetree table):
          1,MN:/etc
          2,server1:/etc
 
 


2.
 
 To list the statelite information for an xCAT osimage named "osimage01".
 
 
 .. code-block:: perl
 
   lslite -i osimage01
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
          tmpfs,rw      /etc/adjtime
          tmpfs,rw      /etc/lvm/.cache
          tmpfs,rw      /etc/mtab
          ........
 
 



*****
FILES
*****


/opt/xcat/bin/lslite


********
SEE ALSO
********


noderange(3)|noderange.3, tabdump(8)|tabdump.8

