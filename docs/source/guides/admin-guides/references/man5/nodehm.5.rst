
########
nodehm.5
########

.. highlight:: perl


****
NAME
****


\ **nodehm**\  - a table in the xCAT database.


********
SYNOPSIS
********


\ **nodehm Attributes:**\   \ *node*\ , \ *power*\ , \ *mgt*\ , \ *cons*\ , \ *termserver*\ , \ *termport*\ , \ *conserver*\ , \ *serialport*\ , \ *serialspeed*\ , \ *serialflow*\ , \ *getmac*\ , \ *cmdmapping*\ , \ *consoleondemand*\ , \ *comments*\ , \ *disable*\ 


***********
DESCRIPTION
***********


Settings that control how each node's hardware is managed.  Typically, an additional table that is specific to the hardware type of the node contains additional info.  E.g. the ipmi, mp, and ppc tables.


******************
nodehm Attributes:
******************



\ **node**\ 
 
 The node name or group name.
 


\ **power**\ 
 
 The method to use to control the power of the node. If not set, the mgt attribute will be used.  Valid values: ipmi, blade, hmc, ivm, fsp, kvm, esx, rhevm.  If "ipmi", xCAT will search for this node in the ipmi table for more info.  If "blade", xCAT will search for this node in the mp table.  If "hmc", "ivm", or "fsp", xCAT will search for this node in the ppc table.
 


\ **mgt**\ 
 
 The method to use to do general hardware management of the node.  This attribute is used as the default if power or getmac is not set.  Valid values: ipmi, blade, hmc, ivm, fsp, bpa, kvm, esx, rhevm.  See the power attribute for more details.
 


\ **cons**\ 
 
 The console method. If nodehm.serialport is set, this will default to the nodehm.mgt setting, otherwise it defaults to unused.  Valid values: cyclades, mrv, or the values valid for the mgt attribute.
 


\ **termserver**\ 
 
 The hostname of the terminal server.
 


\ **termport**\ 
 
 The port number on the terminal server that this node is connected to.
 


\ **conserver**\ 
 
 The hostname of the machine where the conserver daemon is running.  If not set, the default is the xCAT management node.
 


\ **serialport**\ 
 
 The serial port for this node, in the linux numbering style (0=COM1/ttyS0, 1=COM2/ttyS1).  For SOL on IBM blades, this is typically 1.  For rackmount IBM servers, this is typically 0.
 


\ **serialspeed**\ 
 
 The speed of the serial port for this node.  For SOL this is typically 19200.
 


\ **serialflow**\ 
 
 The flow control value of the serial port for this node.  For SOL this is typically 'hard'.
 


\ **getmac**\ 
 
 The method to use to get MAC address of the node with the getmac command. If not set, the mgt attribute will be used.  Valid values: same as values for mgmt attribute.
 


\ **cmdmapping**\ 
 
 The fully qualified name of the file that stores the mapping between PCM hardware management commands and xCAT/third-party hardware management commands for a particular type of hardware device.  Only used by PCM.
 


\ **consoleondemand**\ 
 
 This overrides the value from site.consoleondemand. Set to 'yes', 'no', '1' (equivalent to 'yes'), or '0' (equivalent to 'no'). If not set, the default is the value from site.consoleondemand.
 


\ **comments**\ 
 
 Any user-written notes.
 


\ **disable**\ 
 
 Set to 'yes' or '1' to comment out this row.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ 

