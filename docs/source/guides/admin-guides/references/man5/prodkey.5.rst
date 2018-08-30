
#########
prodkey.5
#########

.. highlight:: perl


****
NAME
****


\ **prodkey**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **prodkey Attributes:**\   \ *node*\ , \ *product*\ , \ *key*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Specify product keys for products that require them


*******************
prodkey Attributes:
*******************



\ **node**\ 
 
 The node name or group name.
 


\ **product**\ 
 
 A string to identify the product (for OSes, the osname would be used, i.e. wink28
 


\ **key**\ 
 
 The product key relevant to the aforementioned node/group and product combination
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

