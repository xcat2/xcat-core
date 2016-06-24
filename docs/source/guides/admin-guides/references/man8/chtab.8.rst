
#######
chtab.8
#######

.. highlight:: perl


****
NAME
****


\ **chtab**\  - Add, delete or update rows in the database tables.


********
SYNOPSIS
********


\ **chtab**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **chtab**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **chtab**\  [\ *keycolname=keyvalue*\ ] [\ *tablename.colname=newvalue*\ ]

\ **chtab**\  [\ *keycolname=keyvalue*\ ] [\ *tablename.colname+=newvalue*\ ]

\ **chtab -d**\  [\ *keycolname=keyvalue*\ ] [\ *tablename.colname=newvalue*\ ]


***********
DESCRIPTION
***********


The chtab command adds, deletes or updates the attribute value in the specified table.column for the specified keyvalue.  Normally, the given value will completely replace the current attribute value.  But if "+=" is used instead of "=", the specified value will be appended to the coma separated list of the attribute, if it is not already there.

The chtab is designed to work without passing xcatd, so it's out of control of policy mechanism.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-v**\           Command Version.

\ **-d**\           Delete option.


************
RETURN VALUE
************



0.  The command completed successfully.



1.  An error has occurred.




********
EXAMPLES
********



1.  To add a node=node1 to the nodelist table with groups=all:
 
 
 .. code-block:: perl
 
   chtab  node=node1 nodelist.groups=all
 
 


2. To add a keyword (tftpdir) and value (/tftpboot) to the site table:
 
 
 .. code-block:: perl
 
   chtab  key=tftpdir site.value=/tftpboot
 
 


3.  To add node1 to the  nodetype table with os=rhel5:
 
 
 .. code-block:: perl
 
   chtab  node=node1 nodetype.os=rhel5
 
 


4.  To change node1 in nodetype table setting os=sles:
 
 
 .. code-block:: perl
 
   chtab  node=node1 nodetype.os=sles
 
 


5. To change node1 by appending otherpkgs to the postbootscripts field in the postscripts table:
 
 
 .. code-block:: perl
 
   chtab node=node1 postscripts.postbootscripts+=otherpkgs
 
 


6. To delete node1 from nodetype table:
 
 
 .. code-block:: perl
 
   chtab -d node=node1 nodetype
 
 



*****
FILES
*****


/opt/xcat/bin/chtab


********
SEE ALSO
********


tabdump(8)|tabdump.8, tabedit(8)|tabedit.8

