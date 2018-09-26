
#####
vpd.5
#####

.. highlight:: perl


****
NAME
****


\ **vpd**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **vpd Attributes:**\   \ *node*\ , \ *serial*\ , \ *mtm*\ , \ *side*\ , \ *asset*\ , \ *uuid*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


The Machine type, Model, and Serial numbers of each node.


***************
vpd Attributes:
***************



\ **node**\ 
 
 The node name or group name.
 


\ **serial**\ 
 
 The serial number of the node.
 


\ **mtm**\ 
 
 The machine type and model number of the node.  E.g. 7984-6BU
 


\ **side**\ 
 
 <BPA>-<port> or <FSP>-<port>. The side information for the BPA/FSP. The side attribute refers to which BPA/FSP, A or B, which is determined by the slot value returned from lsslp command. It also lists the physical port within each BPA/FSP which is determined by the IP address order from the lsslp response. This information is used internally when communicating with the BPAs/FSPs
 


\ **asset**\ 
 
 A field for administrators to use to correlate inventory numbers they may have to accommodate
 


\ **uuid**\ 
 
 The UUID applicable to the node
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

