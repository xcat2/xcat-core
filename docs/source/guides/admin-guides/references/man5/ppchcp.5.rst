
########
ppchcp.5
########

.. highlight:: perl


****
NAME
****


\ **ppchcp**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **ppchcp Attributes:**\   \ *hcp*\ , \ *username*\ , \ *password*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Info necessary to use HMCs and IVMs as hardware control points for LPARs.


******************
ppchcp Attributes:
******************



\ **hcp**\ 
 
 Hostname of the HMC or IVM.
 


\ **username**\ 
 
 Userid of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is hscroot for HMCs and padmin for IVMs.
 


\ **password**\ 
 
 Password of the HMC or IVM.  If not filled in, xCAT will look in the passwd table for key=hmc or key=ivm.  If not in the passwd table, the default used is abc123 for HMCs and padmin for IVMs.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

