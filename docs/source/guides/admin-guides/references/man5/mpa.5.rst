
#####
mpa.5
#####

.. highlight:: perl


****
NAME
****


\ **mpa**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **mpa Attributes:**\   \ *mpa*\ , \ *username*\ , \ *password*\ , \ *displayname*\ , \ *slots*\ , \ *urlpath*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Contains info about each Management Module and how to access it.


***************
mpa Attributes:
***************



\ **mpa**\ 
 
 Hostname of the management module.
 


\ **username**\ 
 
 Userid to use to access the management module.
 


\ **password**\ 
 
 Password to use to access the management module.  If not specified, the key=blade row in the passwd table is used as the default.
 


\ **displayname**\ 
 
 Alternative name for BladeCenter chassis. Only used by PCM.
 


\ **slots**\ 
 
 The number of available slots in the chassis. For PCM, this attribute is used to store the number of slots in the following format:  <slot rows>,<slot columns>,<slot orientation>  Where:
 
 
 .. code-block:: perl
 
                   <slot rows>  = number of rows of slots in chassis
                   <slot columns> = number of columns of slots in chassis
                   <slot orientation> = set to 0 if slots are vertical, and set to 1 if slots of horizontal
 
 


\ **urlpath**\ 
 
 URL path for the Chassis web interface. The full URL is built as follows: <hostname>/<urlpath>
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

