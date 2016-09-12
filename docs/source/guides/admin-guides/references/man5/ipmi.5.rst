
######
ipmi.5
######

.. highlight:: perl


****
NAME
****


\ **ipmi**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **ipmi Attributes:**\   \ *node*\ , \ *bmc*\ , \ *bmcport*\ , \ *taggedvlan*\ , \ *bmcid*\ , \ *username*\ , \ *password*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Settings for nodes that are controlled by an on-board BMC via IPMI.


****************
ipmi Attributes:
****************



\ **node**\ 
 
 The node name or group name.
 


\ **bmc**\ 
 
 The hostname of the BMC adapter.
 


\ **bmcport**\ 
 
 In systems with selectable shared/dedicated ethernet ports, this parameter can be used to specify the preferred port. 0 means use the shared port, 1 means dedicated, blank is to not assign.
 
 
 .. code-block:: perl
 
             The following special cases exist for IBM System x servers:
  
             For x3755 M3 systems, 0 means use the dedicated port, 1 means
             shared, blank is to not assign.
  
         For certain systems which have a mezzaine or ML2 adapter, there is a second
         value to include:
  
  
             For x3750 M4 (Model 8722):
  
  
             0 2   1st 1Gbps interface for LOM
  
             0 0   1st 10Gbps interface for LOM
  
             0 3   2nd 1Gbps interface for LOM
  
             0 1   2nd 10Gbps interface for LOM
  
  
             For  x3750 M4 (Model 8752), x3850/3950 X6, dx360 M4, x3550 M4, and x3650 M4:
  
  
             0     Shared (1st onboard interface)
  
             1     Dedicated
  
             2 0   First interface on ML2 or mezzanine adapter
  
             2 1   Second interface on ML2 or mezzanine adapter
  
             2 2   Third interface on ML2 or mezzanine adapter
  
             2 3   Fourth interface on ML2 or mezzanine adapter
 
 


\ **taggedvlan**\ 
 
 bmcsetup script will configure the network interface of the BMC to be tagged to the VLAN specified.
 


\ **bmcid**\ 
 
 Unique identified data used by discovery processes to distinguish known BMCs from unrecognized BMCs
 


\ **username**\ 
 
 The BMC userid.  If not specified, the key=ipmi row in the passwd table is used as the default.
 


\ **password**\ 
 
 The BMC password.  If not specified, the key=ipmi row in the passwd table is used as the default.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

