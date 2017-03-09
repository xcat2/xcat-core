
########
passwd.5
########

.. highlight:: perl


****
NAME
****


\ **passwd**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **passwd Attributes:**\   \ *key*\ , \ *username*\ , \ *password*\ , \ *cryptmethod*\ , \ *authdomain*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains default userids and passwords for xCAT to access cluster components.  In most cases, xCAT will also actually set the userid/password in the relevant component when it is being configured or installed.  Userids/passwords for specific cluster components can be overidden in other tables, e.g. mpa, ipmi, ppchcp, etc.


******************
passwd Attributes:
******************



\ **key**\ 
 
 The type of component this user/pw is for.  Valid values: blade (management module), ipmi (BMC), system (nodes), omapi (DHCP), hmc, ivm, cec, frame, switch.
 


\ **username**\ 
 
 The default userid for this type of component
 


\ **password**\ 
 
 The default password for this type of component
 


\ **cryptmethod**\ 
 
 Indicates the method that was used to encrypt the password attribute.  On AIX systems, if a value is provided for this attribute it indicates that the password attribute is encrypted.  If the cryptmethod value is not set it indicates the password is a simple string value. On Linux systems, the cryptmethod can be set to md5, sha256 or sha512. If not set, sha256 will be used as default.
 


\ **authdomain**\ 
 
 The domain in which this entry has meaning, e.g. specifying different domain administrators per active directory domain
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

