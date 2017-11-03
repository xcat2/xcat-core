
########
zvmivp.5
########

.. highlight:: perl


****
NAME
****


\ **zvmivp**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **zvmivp Attributes:**\   \ *id*\ , \ *ip*\ , \ *schedule*\ , \ *last_run*\ , \ *type_of_run*\ , \ *access_user*\ , \ *orch_parms*\ , \ *prep_parms*\ , \ *main_ivp_parms*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


List of z/VM Installation Verification Procedures (IVPs) to be periodically run.


******************
zvmivp Attributes:
******************



\ **id**\ 
 
 Unique identifier associated with the IVP run, e.g. 1.
 


\ **ip**\ 
 
 IP address of the target system, either the IP of the OpenStack compute node or the xCAT management node.
 


\ **schedule**\ 
 
 The hours (0-24) that the IVP should be run.  Multiple hours are separated by a blank.
 


\ **last_run**\ 
 
 The last time the IVP was run specified as a set of 3 blank delimeted words: year, Julian date, and hour (in 24 hour format).
 


\ **type_of_run**\ 
 
 The type of run requested, 'fullivp' or 'basicivp'.
 


\ **access_user**\ 
 
 User on the OpenStack node that is used to: push the IVP preparation script to the OpenStack system, drive the preparation script to validate the OpenStack configuration files, and return the created driver script to the xCAT MN system for the next part of the IVP.  This user should be able to access the OpenStack configuration files that are scanned by the IVP.
 


\ **orch_parms**\ 
 
 Parameters to pass to the IVP orchestrator script, verifynode.
 


\ **prep_parms**\ 
 
 Parameters to pass to the phase 1 IVP preparation script.
 


\ **main_ivp_parms**\ 
 
 Parameters to pass to the main IVP script.
 


\ **comments**\ 
 
 Any user provided notes or description of the run.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to disable this IVP run.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

