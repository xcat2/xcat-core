
#####
ppc.5
#####

.. highlight:: perl


****
NAME
****


\ **ppc**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **ppc Attributes:**\   \ *node*\ , \ *hcp*\ , \ *id*\ , \ *pprofile*\ , \ *parent*\ , \ *nodetype*\ , \ *supernode*\ , \ *sfp*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


List of system p hardware: HMCs, IVMs, FSPs, BPCs, CECs, Frames.


***************
ppc Attributes:
***************



\ **node**\ 
 
 The node name or group name.
 


\ **hcp**\ 
 
 The hardware control point for this node (HMC, IVM, Frame or CEC).  Do not need to set for BPAs and FSPs.
 


\ **id**\ 
 
 For LPARs: the LPAR numeric id; for CECs: the cage number; for Frames: the frame number.
 


\ **pprofile**\ 
 
 The LPAR profile that will be used the next time the LPAR is powered on with rpower. For DFM, the pprofile attribute should be set to blank
 


\ **parent**\ 
 
 For LPARs: the CEC; for FSPs: the CEC; for CEC: the frame (if one exists); for BPA: the frame; for frame: the building block number (which consists 1 or more service nodes and compute/storage nodes that are serviced by them - optional).
 


\ **nodetype**\ 
 
 The hardware type of the node. Only can be one of fsp, bpa, cec, frame, ivm, hmc and lpar
 


\ **supernode**\ 
 
 Indicates the connectivity of this CEC in the HFI network. A comma separated list of 2 ids. The first one is the supernode number the CEC is part of. The second one is the logical location number (0-3) of this CEC within the supernode.
 


\ **sfp**\ 
 
 The Service Focal Point of this Frame. This is the name of the HMC that is responsible for collecting hardware service events for this frame and all of the CECs within this frame.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

