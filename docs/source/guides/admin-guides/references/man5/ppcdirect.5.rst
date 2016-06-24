
###########
ppcdirect.5
###########

.. highlight:: perl


****
NAME
****


\ **ppcdirect**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **ppcdirect Attributes:**\   \ *hcp*\ , \ *username*\ , \ *password*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Info necessary to use FSPs/BPAs to control system p CECs/Frames.


*********************
ppcdirect Attributes:
*********************



\ **hcp**\ 
 
 Hostname of the FSPs/BPAs(for ASMI) and CECs/Frames(for DFM).
 


\ **username**\ 
 
 Userid of the FSP/BPA(for ASMI) and CEC/Frame(for DFM).  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.
 


\ **password**\ 
 
 Password of the FSP/BPA(for ASMI) and CEC/Frame(for DFM).  If not filled in, xCAT will look in the passwd table for key=fsp.  If not in the passwd table, the default used is admin.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

