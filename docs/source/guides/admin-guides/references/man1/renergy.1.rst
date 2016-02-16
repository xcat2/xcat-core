
#########
renergy.1
#########

.. highlight:: perl


************
\ **NAME**\ 
************


\ **renergy**\  - remote energy management tool


****************
\ **SYNOPSIS**\ 
****************


\ **renergy**\  [\ **-h**\  | \ **-**\ **-help**\ ]

\ **renergy**\  [\ **-v**\  | \ **-**\ **-version**\ ]

\ **Power 6 server specific :**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [savingstatus] [cappingstatus] [cappingmaxmin] [cappingvalue] [cappingsoftmin] [averageAC] [averageDC] [ambienttemp] [exhausttemp] [CPUspeed] [syssbpower] [sysIPLtime]**\ }

\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **savingstatus={on | off} | cappingstatus={on | off} | cappingwatt=watt | cappingperc=percentage**\ }

\ **Power 7 server specific :**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [savingstatus] [dsavingstatus] [cappingstatus] [cappingmaxmin] [cappingvalue] [cappingsoftmin] [averageAC] [averageDC] [ambienttemp] [exhausttemp] [CPUspeed] [syssbpower] [sysIPLtime] [fsavingstatus] [ffoMin] [ffoVmin] [ffoTurbo] [ffoNorm] [ffovalue]**\ }

\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **savingstatus={on | off} | dsavingstatus={on-norm | on-maxp | off} | fsavingstatus={on | off} | ffovalue=MHZ | cappingstatus={on | off} | cappingwatt=watt | cappingperc=percentage**\ }

\ **Power 8 server specific :**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [savingstatus] [dsavingstatus] [averageAC] [averageAChistory] [averageDC] [averageDChistory] [ambienttemp] [ambienttemphistory] [exhausttemp] [exhausttemphistory] [fanspeed] [fanspeedhistory] [CPUspeed] [CPUspeedhistory] [syssbpower] [sysIPLtime] [fsavingstatus] [ffoMin] [ffoVmin] [ffoTurbo] [ffoNorm] [ffovalue]**\ }

\ **renergy**\  \ *noderange*\  \ **[-V] {savingstatus={on | off} | dsavingstatus={on-norm | on-maxp | off} | fsavingstatus={on | off} | ffovalue=MHZ }**\ 

\ *NOTE:*\  The setting operation for \ **Power 8**\  server is only supported 
for the server which is running in PowerVM mode. Do NOT run the setting 
for the server which is running in OPAL mode.

\ **BladeCenter specific :**\ 


\ **For Management Modules:**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | pd1all | pd2all | [pd1status] [pd2status] [pd1policy] [pd2policy] [pd1powermodule1] [pd1powermodule2] [pd2powermodule1] [pd2powermodule2] [pd1avaiablepower] [pd2avaiablepower] [pd1reservedpower] [pd2reservedpower] [pd1remainpower] [pd2remainpower] [pd1inusedpower] [pd2inusedpower] [availableDC] [averageAC] [thermaloutput] [ambienttemp] [mmtemp]**\ }

\ **For a blade server nodes:**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [averageDC] [capability] [cappingvalue] [CPUspeed] [maxCPUspeed] [savingstatus] [dsavingstatus]**\ }

\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **savingstatus={on | off} | dsavingstatus={on-norm | on-maxp | off}**\ }

\ **Flex specific :**\ 


\ **For Flex Management Modules:**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [powerstatus] [powerpolicy] [powermodule] [avaiablepower] [reservedpower] [remainpower] [inusedpower] [availableDC] [averageAC] [thermaloutput] [ambienttemp] [mmtemp]**\ }

\ **For Flex node (power and x86):**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **all | [averageDC] [capability] [cappingvalue] [cappingmaxmin] [cappingmax] [cappingmin] [cappingGmin] [CPUspeed] [maxCPUspeed] [savingstatus] [dsavingstatus]**\ }

\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **cappingstatus={on | off} | cappingwatt=watt | cappingperc=percentage | savingstatus={on | off} | dsavingstatus={on-norm | on-maxp | off}**\ }

\ **iDataPlex specific :**\ 


\ **renergy**\  \ *noderange*\  [\ **-V**\ ] [{\ **cappingmaxmin | cappingmax | cappingmin}] [cappingstatus] [cappingvalue] [relhistogram]**\ }

\ **renergy**\  \ *noderange*\  [\ **-V**\ ] {\ **cappingstatus={on | enable | off | disable} | {cappingwatt|cappingvalue}=watt**\ }

\ **OpenPOWER server specific :**\ 


\ **renergy**\  \ *noderange*\  {\ **powerusage | temperature**\ }


*******************
\ **DESCRIPTION**\ 
*******************


This \ **renergy**\  command can be used to manage the energy consumption of
IBM servers which support IBM EnergyScale technology. Through this command, 
user can query and set the power saving and power capping status, and also can 
query the average consumed energy, the ambient and exhaust temperature, 
the processor frequency for a server.

\ **renergy**\  command supports IBM POWER6, POWER7 and POWER8 rack-mounted servers,
BladeCenter management modules, blade servers, and iDataPlex servers. 
For \ *Power6*\  and \ *Power7*\  rack-mounted servers, the following specific hardware types are supported:
\ *8203-E4A*\ , \ *8204-E8A*\ , \ *9125-F2A*\ , \ *8233-E8B*\ , \ *8236-E8C*\ .
For \ *Power8*\  server, there's no hardware type restriction.

The parameter \ *noderange*\  needs to be specified for the \ **renergy**\  command to 
get the target servers. The \ *noderange*\  should be a list of CEC node names, blade 
management module node names or blade server node names. Lpar name
is not acceptable here.

\ **renergy**\  command can accept multiple of energy attributes to query or one of energy 
attribute to set. If only the attribute name is specified, without the '=', \ **renergy**\  
gets and displays the current value. Otherwise, if specifying the attribute with '=' like 
'savingstatus=on', \ **renergy**\  will set the attribute savingstatus to value 'on'.

The attributes listed in the \ **SYNOPSIS**\  section are which ones can be handled by 
\ **renergy**\  command. But for each specific type of server, there are some attributes that
are not supported. If user specifies an attribute which is not supported by a specific
server, the return value of this attribute will be 'na'.

\ **Note**\ : the options \ *powerusage*\  and \ *temperature*\  are only supported for \ **OpenPOWER servers**\ .

The supported attributes for each specific system p hardware type is listed as follows:


\ **8203-E4A**\ , \ **8204-E8A**\ 


Supported attributes:

\ **Query**\ : savingstatus,cappingstatus,cappingmin,cappingmax,
cappingvalue,cappingsoftmin,averageAC,averageDC,ambienttemp,
exhausttemp,CPUspeed,syssbpower,sysIPLtime

\ **Set**\ :   savingstatus,cappingstatus,cappingwatt,cappingperc

\ **9125-F2A**\ 


Supported attributes:

\ **Query**\ : savingstatus,averageAC,ambienttemp,exhausttemp,
CPUspeed

\ **Set**\ :   savingstatus

\ **8233-E8B**\ , \ **8236-E8C**\ 


Supported attributes:

\ **Query**\ : savingstatus,dsavingstatus,cappingstatus,cappingmin,
cappingmax,cappingvalue,cappingsoftmin,averageAC,averageDC,
ambienttemp,exhausttemp,CPUspeed,syssbpower,sysIPLtime

\ **Set**\ :   savingstatus,dsavingstatus,cappingstatus,cappingwatt,
cappingperc

\ **9125-F2C**\ , \ **9119-FHB**\ 


Supported attributes:

\ **Query**\ : savingstatus,dsavingstatus,cappingstatus,cappingmin,
cappingmax,cappingvalue,cappingsoftmin,averageAC,averageDC,
ambienttemp,exhausttemp,CPUspeed,syssbpower,sysIPLtime,
fsavingstatus,ffoMin,ffoVmin,ffoTurbo,ffoNorm,ffovalue

\ **Set**\ :   savingstatus,dsavingstatus,cappingstatus,cappingwatt,
cappingperc,fsavingstatus,ffovalue

\ **Non of Above**\ 


For the machine type which is not in the above list, the following 
attributes can be tried but not guaranteed:

\ **Query**\ : savingstatus,dsavingstatus,cappingstatus,cappingmin,
cappingmax,,cappingvalue,cappingsoftmin,averageAC,averageDC,
ambienttemp,exhausttemp,CPUspeed,syssbpower,sysIPLtime

\ **Set**\ :  savingstatus,dsavingstatus,cappingstatus,cappingwatt,
cappingperc

Note:
For system P CEC nodes, each query operation for attribute CPUspeed, averageAC 
or averageDC needs about 30 seconds to complete. The query for others attributes
will get response immediately.


*********************
\ **PREREQUISITES**\ 
*********************


For the \ *Power6*\  and \ *Power7*\  nodes, the \ **renergy**\  command depends 
on the Energy Management Plugin \ **xCAT-pEnergy**\  to 
communicate with server.  \ **xCAT-pEnergy**\  can be downloaded from the IBM web site: 
http://www.ibm.com/support/fixcentral/. (Other Software -> EM)

NOTE: \ *Power8*\  nodes don't need this specific energy management package.

For iDataPlex nodes, the \ **renergy**\  command depends 
on the Energy Management Plugin \ **xCAT-xEnergy**\  to 
communicate with server.  This plugin must be requested from IBM.

(The support for BladeCenter energy management is built into base xCAT,
so no additional plugins are needed for BladeCenter.)


***************
\ **OPTIONS**\ 
***************



\ **-h | -**\ **-help**\ 
 
 Display the usage message.
 


\ **-v | -**\ **-version**\ 
 
 Display the version information.
 


\ **-V**\ 
 
 Verbose output.
 


\ **all**\ 
 
 Query all energy attributes which supported by the specific 
 type of hardware.
 
 For \ *Power8*\  machines, will not display the attributes
 for historical records.
 


\ **pd1all**\ 
 
 Query all energy attributes of the power domain 1 for blade
 management module node.
 


\ **pd2all**\ 
 
 Query all energy attributes of the power domain 2 for blade
 management module node.
 


\ **ambienttemp**\ 
 
 Query the current ambient temperature. (Unit is centigrade)
 


\ **ambienttemphistory**\ 
 
 Query the historical records which were generated in last one hour for \ **ambienttemp**\ .
 


\ **availableDC**\ 
 
 Query the total DC power available for the entire blade center chassis.
 


\ **averageAC**\ 
 
 Query the average power consumed (Input). (Unit is watt)
 
 Note: For 9125-F2A,9125-F2C server, the value of attribute 
 averageAC is the aggregate for all of the servers in a rack.
 
 Note: For Blade Center, the value of attribute 
 averageAC is the total AC power being consumed by all modules
 in the chassis. It also includes power consumed by the Chassis 
 Cooling Devices for BCH chassis.
 


\ **averageAChistory**\ 
 
 Query the historical records which were generated in last one hour for \ **averageAC**\ .
 


\ **averageDC**\ 
 
 Query the average power consumed (Output). (Unit is watt)
 


\ **averageDChistory**\ 
 
 Query the historical records which were generated in last one hour for \ **averageDC**\ .
 


\ **capability**\ 
 
 Query the Power Capabilities of the blade server.
 
 staticPowerManagement: the module with the static worst case power values.
 
 fixedPowermanagement: the module with the static power values but ability 
 to throttle.
 
 dynamicPowerManagement: the module with power meter capability, measurement 
 enabled, but capping disabled.
 
 dynamicPowerMeasurement1: the module with power meter capability, measurement 
 enabled, phase 1 only
 
 dynamicPowerMeasurement2: the module with power meter capability, measurement 
 enabled, phase 2 or higher
 
 dynamicPowerMeasurementWithPowerCapping: the module with power meter capability, 
 both measurement and capping enabled, phase 2 or higher
 


\ **cappingGmin**\ 
 
 Query the Guaranteed Minimum power capping value in watts.
 


\ **cappingmax**\ 
 
 Query the Maximum of power capping value in watts.
 


\ **cappingmaxmin**\ 
 
 Query the Maximum and Minimum of power capping value in watts.
 


\ **cappingmin**\ 
 
 Query the Minimum of power capping value in watts.
 


\ **cappingperc**\ =\ **percentage**\ 
 
 Set the power capping value base on the percentage of 
 the max-min of capping value which getting from 
 \ *cappingmaxmim*\  attribute. The valid value must be 
 from 0 to 100.
 


\ **cappingsoftmin**\ 
 
 Query the minimum value that can be assigned to power 
 capping without guaranteed enforceability. (Unit is watt)
 


\ **cappingstatus**\ 
 
 Query the power capping status. The result should be 'on' 
 or 'off'.
 


\ **cappingstatus**\ ={\ **on**\  | \ **off**\ }
 
 Set the power capping status. The value must be 'on' 
 or 'off'. This is the switch to turn on or turn off the 
 power capping function.
 


\ **cappingvalue**\ 
 
 Query the current power capping value. (Unit is watt)
 


\ **cappingwatt**\ =\ **watt**\ 
 
 Set the power capping value base on the watt unit.
 
 If the 'watt' >  maximum of \ *cappingmaxmin*\  or 'watt' 
 < \ *cappingsoftmin*\ , the setting operation 
 will be failed. If the 'watt' > \ *cappingsoftmin*\  and 
 'watt' < minimum of \ *cappingmaxmin*\ , the value can NOT be 
 guaranteed.
 


\ **CPUspeed**\ 
 
 Query the effective processor frequency. (Unit is MHz)
 


\ **CPUspeedhistory**\ 
 
 Query the historical records which were generated in last one hour for \ **CPUspeed**\ 
 


\ **dsavingstatus**\ 
 
 Query the dynamic power saving status. The result should 
 be 'on-norm', 'on-maxp'  or 'off'.
 
 If turning on the dynamic power saving, the processor 
 frequency and voltage will be dropped dynamically based on 
 the core utilization. It supports two modes for turn on state:
 
 \ *on-norm*\  - means normal, the processor frequency cannot 
 exceed the nominal value;
 
 \ *on-maxp*\  - means maximum performance, the processor 
 frequency can exceed the nominal value.
 


\ **dsavingstatus**\ ={\ **on-norm**\  | \ **on-maxp**\  | \ **off**\ }
 
 Set the dynamic power saving. The value must be 'on-norm', 
 'on-maxp' or 'off'.
 
 The dsavingstatus setting operation needs about 2 minutes 
 to take effect. (The used time depends on the hardware type)
 
 The \ **dsavingstatus**\  only can be turned on when the 
 \ **savingstatus**\  is in turn off status.
 


\ **exhausttemp**\ 
 
 Query the current exhaust temperature. (Unit is centigrade)
 


\ **exhausttemphistory**\ 
 
 Query the historical records which were generated in last one hour for \ **exhausttemp**\ 
 


\ **fanspeed**\ 
 
 Query the fan speed for all the fans which installed in this node. (Unit is RPM - Rotations Per Minute))
 
 If there are multiple fans for a node, multiple lines will be output. And a fan name in bracket will be 
 appended after \ **fanspped**\  attribute name.
 


\ **fanspeedhistory**\ 
 
 Query the historical records which were generated in last one hour for \ **fanspeed**\ .
 


\ **ffoMin**\ 
 
 Query the minimum cpu frequency which can be set for FFO. (Fixed 
 Frequency Override)
 


\ **ffoNorm**\ 
 
 Query the maximum cpu frequency which can be set for FFO.
 


\ **ffoTurbo**\ 
 
 Query the advertised maximum cpu frequency (selling point).
 


\ **ffoVmin**\ 
 
 Query the minimum cpu frequency which can be set for dropping down 
 the voltage to save power. That means when you drop the cpu 
 frequency from the ffoVmin to ffoVmin, the voltage won't change, 
 then there's no obvious power to be saved.
 


\ **ffovalue**\ 
 
 Query the current value of FFO.
 


\ **ffovalue**\ =\ **MHZ**\ 
 
 Set the current value of FFO. The valid value of ffovalue should 
 be between the ffoMin and ffoNorm.
 
 Note1: Due to the limitation of firmware, the frequency in the range 
 3501 MHz - 3807 MHz can NOT be set to ffovalue. This range may be 
 changed in future.
 
 Note2: The setting will take effect only when the fsavingstatus is in 
 'on' status. But you need to set the ffovalue to a valid value before 
 enabling the fsavingstatus. (It's a limitation of the initial firmware 
 and will be fixed in future.)
 
 The ffovalue setting operation needs about 1 minute to take effect.
 


\ **fsavingstatus**\ 
 
 Query the status of FFO. The result should be 'on' or 'off'. 
 'on' - enable; 'off' - disable.
 


\ **fsavingstatus**\ ={\ **on**\  | \ **off**\ }
 
 Set the status of FFO. The value must be 'on' or 'off'.
 
 'on' - enable. It will take effect only when the \ **ffovalue**\  
 has been set to a valid value.
 
 'off' -disable. It will take effect immediately.
 
 Note: See the Note2 of ffovalue=MHZ.
 


\ **maxCPUspeed**\ 
 
 Query the maximum processor frequency. (Unit is MHz)
 


\ **mmtemp**\ 
 
 Query the current temperature of management module. 
 (Unit is centigrade)
 


\ **pd1status | powerstatus**\ 
 
 Query the status of power domain 1 for blade management 
 module node.
 
 Note: for the attribute without the leading 'pd1' which 
 means there's only one power doamin in the chassis.
 


\ **pd1policy | powerpolicy**\ 
 
 Query the power management policy of power domain 1.
 


\ **pd1powermodule1 | powermodule**\ 
 
 Query the First Power Module capacity in power domain 1.
 


\ **pd1powermodule2 | powermodule**\ 
 
 Query the Second Power Module capacity in power domain 1.
 


\ **pd1avaiablepower | avaiablepower**\ 
 
 Query the total available power in power domain 1.
 


\ **pd1reservedpower | reservedpower**\ 
 
 Query the power that has been reserved for power domain 1.
 


\ **pd1remainpower | remainpower**\ 
 
 Query the remaining power available in power domain 1.
 


\ **pd1inusedpower | inusedpower**\ 
 
 Query the total power being used in power domain 1.
 


\ **pd2status**\ 
 
 Query the status of power domain 2 for blade management 
 module node.
 


\ **pd2policy**\ 
 
 Query the power management policy of power domain 2.
 


\ **pd2powermodule1**\ 
 
 Query the First Power Module capacity in power domain 2.
 


\ **pd2powermodule2**\ 
 
 Query the Second Power Module capacity in power domain 2.
 


\ **pd2avaiablepower**\ 
 
 Query the total available power in power domain 2.
 


\ **pd2reservedpower**\ 
 
 Query the power that has been reserved for power domain 2.
 


\ **pd2remainpower**\ 
 
 Query the remaining power available in power domain 2.
 


\ **pd2inusedpower**\ 
 
 Query the total power being used in power domain 2.
 


\ **relhistogram**\ 
 
 Query histogram data for wattage information
 


\ **savingstatus**\ 
 
 Query the static power saving status. The result should be 
 'on' or 'off'. 'on' - enable; 'off' - disable.
 


\ **savingstatus**\ ={\ **on**\  | \ **off**\ }
 
 Set the static power saving. The value must be 'on' or 'off'.
 
 If turning on the static power saving, the processor frequency 
 and voltage will be dropped to a fixed value to save energy.
 
 The savingstatus setting operation needs about 2 minutes to 
 take effect. (The used time depends on the hardware type)
 
 The \ **savingstatus**\  only can be turned on when the 
 \ **dsavingstatus**\  is in turn off status.
 


\ **sysIPLtime**\ 
 
 Query the time used from FSP standby to OS standby. 
 (Unit is Second)
 


\ **syssbpower**\ 
 
 Query the system power consumed prior to power on. 
 (Unit is Watt)
 


\ **thermaloutput**\ 
 
 Query the thermal output (load) in BTUs per hour for the blade 
 center chassis.
 


\ **powerusage**\ 
 
 Query System Power Statistics with DCMI (Data Center Manageability Interface).
 


\ **temperature**\ 
 
 Query the temperature from DCMI (Data Center Manageability Interface) Temperature sensor. 
 Currently, only CPU temperature and baseboard temperature sensor available for OpenPOWER servers.
 



********************
\ **RETURN VALUE**\ 
********************


0 The command completed successfully.

1 An error has occurred.


****************
\ **EXAMPLES**\ 
****************



1. Query all attributes which CEC1,CEC2 supported.
 
 
 .. code-block:: perl
 
   renergy CEC1,CEC2 all
 
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      CEC1: savingstatus: off
      CEC1: dsavingstatus: off
      CEC1: cappingstatus: off
      CEC1: cappingmin: 1953 W
      CEC1: cappingmax: 2358 W
      CEC1: cappingvalue: 2000 W
      CEC1: cappingsoftmin: 304 W
      CEC1: averageAC: na
      CEC1: averageDC: na
      CEC1: ambienttemp: na
      CEC1: exhausttemp: na
      CEC1: CPUspeed: na
      CEC1: syssbpower: 40 W
      CEC1: sysIPLtime: 900 S
      CEC2: savingstatus: off
      CEC2: cappingstatus: off
      CEC2: cappingmin: 955 W
      CEC2: cappingmax: 1093 W
      CEC2: cappingvalue: 1000 W
      CEC2: cappingsoftmin: 226 W
      CEC2: averageAC: 627 W
      CEC2: averageDC: 531 W
      CEC2: ambienttemp: 25 C
      CEC2: exhausttemp: 40 C
      CEC2: CPUspeed: 4695 MHz
 
 


2. Query the \ **fanspeed**\  attribute for Power8 CEC.
 
 
 .. code-block:: perl
 
   renergy CEC1 fanspeed
 
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A1 00002101): 5947 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A2 00002103): 6081 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A3 00002105): 6108 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A4 00002107): 6000 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A5 00002109): 6013 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-A6 0000210B): 6013 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-E1 0000210C): 4992 RPM
      CEC1: fanspeed (Fan U78CB.001.WZS00MA-E2 0000210D): 5016 RPM
 
 


3. Query the historical records for the \ **CPUspeed**\  attribute. (Power8 CEC)
 
 \ **renergy**\  CEC1 CPUspeedhistory
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      CEC1: CPUspeedhistory: 2027 MHZ: 20141226042900
      CEC1: CPUspeedhistory: 2027 MHZ: 20141226042930
      CEC1: CPUspeedhistory: 2244 MHZ: 20141226043000
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043030
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043100
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043130
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043200
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043230
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043300
      CEC1: CPUspeedhistory: 2393 MHZ: 20141226043330
      ...
 
 


4
 
 Query all the attirbutes for management module node MM1. (For chassis)
 
 
 .. code-block:: perl
 
   renergy MM1 all
 
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      mm1: availableDC: 5880W
      mm1: frontpaneltmp: 18.00 Centigrade
      mm1: inusedAC: 2848W
      mm1: mmtmp: 28.00 Centigrade
      mm1: pd1avaiablepower: 2940W
      mm1: pd1inusedpower: 848W
      mm1: pd1policy: redundantWithoutPerformanceImpact
      mm1: pd1powermodule1: Bay 1: 2940W
      mm1: pd1powermodule2: Bay 2: 2940W
      mm1: pd1remainpower: 1269W
      mm1: pd1reservedpower: 1671W
      mm1: pd1status: 1 - Power domain status is good.
      mm1: pd2avaiablepower: 2940W
      mm1: pd2inusedpower: 1490W
      mm1: pd2policy: redundantWithoutPerformanceImpact
      mm1: pd2powermodule1: Bay 3: 2940W
      mm1: pd2powermodule2: Bay 4: 2940W
      mm1: pd2remainpower: 51W
      mm1: pd2reservedpower: 2889W
      mm1: pd2status: 2 - Warning: Power redundancy does not exist in this power domain.
      mm1: thermaloutput: 9717.376000 BTU/hour
 
 


5. Query all the attirbutes for blade server node blade1.
 
 
 .. code-block:: perl
 
   renergy blade1 all
 
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      blade1: CPUspeed: 4204MHZ
      blade1: averageDC: 227W
      blade1: capability: dynamicPowerMeasurement2
      blade1: cappingvalue: 315W
      blade1: dsavingstatus: off
      blade1: maxCPUspeed: 4204MHZ
      blade1: savingstatus: off
 
 


6. Query the attributes savingstatus, cappingstatus 
and CPUspeed for server CEC1.
 
 
 .. code-block:: perl
 
   renergy CEC1 savingstatus cappingstatus CPUspeed
 
 
 The output of the query operation:
 
 
 .. code-block:: perl
 
      CEC1: savingstatus: off
      CEC1: cappingstatus: on
      CEC1: CPUspeed: 3621 MHz
 
 


7. Turn on the power saving function of CEC1.
 
 
 .. code-block:: perl
 
   renergy CEC1 savingstatus=on
 
 
 The output of the setting operation:
 
 
 .. code-block:: perl
 
      CEC1: Set savingstatus succeeded.         
      CEC1: This setting may need some minutes to take effect.
 
 


8. Set the power capping value base on the percentage of the 
max-min capping value. Here, set it to 50%.
 
 
 .. code-block:: perl
 
   renergy CEC1 cappingperc=50
 
 
 If the maximum capping value of the CEC1 is 850w, and the 
 minimum capping value of the CEC1 is 782w, the Power Capping 
 value will be set as ((850-782)\*50% + 782) = 816w.
 
 The output of the setting operation:
 
 
 .. code-block:: perl
 
      CEC1: Set cappingperc succeeded.
      CEC1: cappingvalue: 816
 
 


9. Query powerusage and temperature for OpenPOWER servers.
 
 
 .. code-block:: perl
 
   renergy ops01 powerusage temperature
 
 
 The output will be like this:
 
 
 .. code-block:: perl
 
      ops01: Current Power                        : 591W
      ops01: Minimum Power over sampling duration : 558W
      ops01: Maximum Power over sampling duration : 607W
      ops01: Average Power over sampling duration : 572W
      ops01: Time Stamp                           : 11/18/2015 - 1:4:1
      ops01: Statistics reporting time period     : 10000 milliseconds
      ops01: Power Measurement                    : Active
      ops01: CPU Temperature Instance 0           : +39 Centigrade
      ops01: Baseboard temperature Instance 0     : +28 Centigrade
 
 



******************
\ **REFERENCES**\ 
******************



1. For more information on 'Power System Energy Management':
 
 http://www-03.ibm.com/systems/power/software/energy/index.html
 


2. EnergyScale white paper for Power6:
 
 http://www-03.ibm.com/systems/power/hardware/whitepapers/energyscale.html
 


3. EnergyScale white paper for Power7:
 
 http://www-03.ibm.com/systems/power/hardware/whitepapers/energyscale7.html
 



*************
\ **FILES**\ 
*************


/opt/xcat/bin/renergy

