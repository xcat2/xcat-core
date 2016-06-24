
###########
nodegrpch.1
###########

.. highlight:: perl


****
NAME
****


\ **nodegrpch**\  - Changes attributes at the group level in the xCAT cluster database.


********
SYNOPSIS
********


\ **nodegrpch**\  \ *group1,group2,...*\  \ *table.column=value*\  [\ *...*\ ]

\ **nodegrpch**\  {\ **-v**\  | \ **-**\ **-version**\ }

\ **nodegrpch**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\ ]


***********
DESCRIPTION
***********


The nodegrpch command is similar to the nodech command, but ensures that the parameters are
declared at the group level rather than the node specific level, and clears conflicting node 
specific overrides of the specified groups.   Using table.column=value will do a 
verbatim assignment.  If ",=" is used instead of "=", the specified value will be prepended to the 
attribute's comma separated list, if it is not already there.  If "^=" is used, the specified 
value will be removed from the attribute's comma separated list, if it is there.  You can also 
use "^=" and ",=" in the same command to essentially replace one item
in the list with another.  (See the Examples section.)

With these operators in mind, the unambiguous assignment operator is '=@'.  If you need, for example, to set
the nodehm.comments to =foo, you would have to do \ *nodegrpch group1 nodehm.comments=@=foo*\ .

See the \ **xcatdb**\  man page for an overview of each table.

The nodegrpch command also supports some short cut names as aliases to common attributes.  See the
\ **nodels**\  man page for details.


*******
OPTIONS
*******



\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1.
 
 To declare all members of ipmi group to have nodehm.mgt be ipmi
 
 
 .. code-block:: perl
 
   nodegrpch ipmi nodehm.mgt=ipmi
 
 



*****
FILES
*****


/opt/xcat/bin/nodegrpch


********
SEE ALSO
********


nodech(1)|nodech.1, nodels(1)|nodels.1, nodeadd(8)|nodeadd.8, noderange(3)|noderange.3

