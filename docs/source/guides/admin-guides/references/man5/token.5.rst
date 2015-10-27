
#######
token.5
#######

.. highlight:: perl


****
NAME
****


\ **token**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **token Attributes:**\   \ *tokenid*\ , \ *username*\ , \ *expire*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The token of users for authentication.


*****************
token Attributes:
*****************



\ **tokenid**\ 
 
 It is a UUID as an unified identify for the user.
 


\ **username**\ 
 
 The user name.
 


\ **expire**\ 
 
 The expire time for this token.
 


\ **comments**\ 
 
 Any user-provided notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

