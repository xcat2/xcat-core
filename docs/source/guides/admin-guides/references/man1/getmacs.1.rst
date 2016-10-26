
#########
getmacs.1
#########

.. highlight:: perl


****
NAME
****


\ **getmacs**\  - Collects node MAC address.


********
SYNOPSIS
********


Common:
=======


\ **getmacs**\  [\ **-h**\ | \ **-**\ **-help**\  | \ **-v**\ | \ **-**\ **-version**\ ]


PPC specific:
=============


\ **getmacs**\  \ *noderange*\  [\ **-F**\  \ *filter*\ ]

\ **getmacs**\  \ *noderange*\  [\ **-M**\ ]

\ **getmacs**\  \ *noderange*\  [\ **-V**\ | \ **-**\ **-verbose**\ ] [\ **-f**\ ] [\ **-d**\ ] [\ **-**\ **-arp**\ ] | [\ **-D**\  {[\ **-S**\  \ *server*\ ] [\ **-G**\  \ *gateway*\ ] [\ **-C**\  \ *client*\ ] [\ **-o**\ ] | [\ **-**\ **-noping**\ ]}]


blade specific:
===============


\ **getmacs**\  \ *noderange*\  [\ **-V**\ | \ **-**\ **-verbose**\ ] [\ **-d**\ ] [\ **-**\ **-arp**\ ] [\ **-i**\  \ *ethN*\  | \ *enN*\ ]



***********
DESCRIPTION
***********


The getmacs command collects MAC address from a single or range of nodes.
Note that on AIX systems, the returned MAC address is not colon-seperated (for example 8ee2245cf004), while on Linux systems the MAC address is colon-seperated (for example 8e:e2:24:5c:f0:04).
If no ping test performed,  getmacs writes the first adapter MAC to the xCAT database.  If ping test performed, getmacs will write the first successfully pinged MAC to xCAT database.

For PPC (using Direct FSP Management) specific:

Note: If network adapters are physically assigned to LPARs, getmacs cannot read the MAC addresses unless perform \ **Discovery**\  with option "\ **-D**\ ", since there is no HMC command to read them and getmacs has to login to open formware. And if the LPARs has never been activated before, getmacs need to be performed with the option "\ **-D**\ " to get theirs MAC addresses.

For PPC (using HMC) specific:

Note: The option "\ **-D**\ " \ **must**\  be used to get MAC addresses of LPARs.

For IBM Flex Compute Node (Compute Node for short) specific:

Note: If "\ **-d**\ " is specified, all the MAC of the blades will be displayed. If no option specified, the first MAC address of the blade will be written to mac table.


*******
OPTIONS
*******


\ **-**\ **-arp**\ 

Read MAC address with ARP protocal.

\ **-C**\ 

Specify the IP address of the partition for ping test. The default is to read from xCAT database if no \ **-C**\  specified.

\ **-d**\ 

Display MAC only. The default is to write the first valid adapter MAC to the xCAT database.

\ **-D**\ 

Perform discovery for mac address.  By default, it will run ping test to test the connection between adapter and xCAT management node. Use '--noping' can skip the ping test to save time. Be aware that in this way, the lpars will be reset.

\ **-f**\ 

Force immediate shutdown of the partition.This flag must be used with -D flag.

\ **-F**\ 

Specify filters to select the correct adapter.  Acceptable filters are Type, MAC_Address, Phys_Port_Loc, Adapter, Port_Group, Phys_Port, Logical_Port, VLan, VSwitch, Curr_Conn_Speed.

\ **-G**\ 

Gateway IP address of the partition.  The default is to read from xCAT database if no \ **-G**\  specified.

\ **-h**\ 

Display usage message.

\ **-M**\ 

Return multiple MAC addresses for the same adapter or port, if available from the hardware.  For some network adapters (e.g. HFI) the MAC can change when there are some recoverable internal errors.  In this case, the hardware can return several MACs that the adapter can potentially have, so that xCAT can put all of them in DHCP.  This allows successful booting, even after a MAC change, but on Linux at this time, it can also cause duplicate IP addresses, so it is currently not recommended on Linux.  By default (without this flag), only a single MAC address is returned for each adapter.

\ **-**\ **-noping**\ 

Only can be used with '-D' to display all the available adapters with mac address but do NOT run ping test.

\ **-o**\ 

Read MAC address when the lpar is in openfirmware state.  This option mush be used with [\ **-D**\ ] option to perform ping test. Before use \ **-o**\ , the lpar must be in openfirmware state.

\ **-S**\ 

The IP address of the machine to ping.  The default is to read from xCAT databse if no \ **-S**\  specified.

\ **-v**\ 

Command Version.

\ **-V**\ 

Verbose output.

\ **-i**\ 

Specify the interface whose mac address will be collected and written into mac table. If 4 mac addresses are returned by option '-d', they all are the mac addresses of the blade. The N can start from 0(map to the eth0 of the blade) to 3. If 5 mac addresses are returned, the 1st mac address must be the mac address of the blade's FSP, so the N will start from 1(map to the eth0 of the blade) to 4.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To retrieve the MAC address for the HMC-managed partition lpar4 and write the first valid adapter MAC to the xCAT database, enter:


.. code-block:: perl

  getmacs lpar4


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  MAC_Address  Phys_Port_Loc  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed
  hea  7607DFB07F02  N/A  N/A  N/A  N/A  N/A  1  ETHERNET0  N/A
  ent U78A1.001.99203B5-P1-T6   00145eb55788 /lhea@23c00614/ethernet@23e00514 unsuccessful physical


2. To retrieve the MAC address with ARP protocal:


.. code-block:: perl

  getmacs lpar4 --arp


Output is similar to:


.. code-block:: perl

  lpar4:
  #IP           MAC_Address
  192.168.0.10  00145eb55788


3. To retrieve the MAC address for the HMC-managed partition lpar4 and display the result only, enter:


.. code-block:: perl

  getmacs lpar4 -d


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  MAC_Address  Phys_Port_Loc  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed
  hea  7607DFB07F02  N/A  N/A  N/A  N/A  N/A  1  ETHERNET0  N/A
  ent U78A1.001.99203B5-P1-T6   00145eb55788 /lhea@23c00614/ethernet@23e00514 unsuccessful physical


4. To retrieve the MAC address for the HMC-managed partition lpar4 with filter Type=hea,VSwitch=ETHERNET0.


.. code-block:: perl

  getmacs lpar4 -F Type=hea,VSwitch=ETHERNET0


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  MAC_Address  Phys_Port_Loc  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed
  hea  7607DFB07F02  N/A  N/A  N/A  N/A  N/A  1  ETHERNET0  N/A


5. To retrieve the MAC address while performing a ping test for the HMC-managed partition lpar4 and display the result only, enter:


.. code-block:: perl

  getmacs lpar4 -d -D -S 9.3.6.49 -G 9.3.6.1 -C 9.3.6.234


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  Location Code   MAC Address      Full Path Name  Ping Result
  ent U9133.55A.10B7D1G-V12-C4-T1 8e:e2:24:5c:f0:04 /vdevice/l-lan@30000004 successful virtual


6. To retrieve the MAC address for Power 775 LPAR using Direct FSP Management without ping test and display the result only, enter:


.. code-block:: perl

  getmacs lpar4 -d


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  Phys_Port_Loc  MAC_Address  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed
  HFI  N/A  02:00:02:00:00:04  N/A  N/A  N/A  N/A  N/A  N/A  N/A


7. To retrieve multiple MAC addresses from Power 775 HFI network adapter using Direct FSP Management, enter:


.. code-block:: perl

  getmacs lpar4 -M


Output is similar to:


.. code-block:: perl

  lpar4:
  #Type  Phys_Port_Loc  MAC_Address  Adapter  Port_Group  Phys_Port  Logical_Port  VLan  VSwitch  Curr_Conn_Speed
  HFI  N/A  02:00:02:00:00:04|02:00:02:00:00:05|02:00:02:00:00:06  N/A  N/A  N/A  N/A  N/A  N/A  N/A


8. To retrieve the MAC address for Power Lpar by '-D' but without ping test.


.. code-block:: perl

  getmacs lpar4 -D --noping


Output is similar to:


.. code-block:: perl

  lpar4:
  # Type  Location Code   MAC Address      Full Path Name  Device Type
  ent U8233.E8B.103A4DP-V3-C3-T1 da:08:4c:4d:d5:03 /vdevice/l-lan@30000003  virtual
  ent U8233.E8B.103A4DP-V3-C4-T1 da:08:4c:4d:d5:04 /vdevice/l-lan@30000004  virtual
  ent U78A0.001.DNWHYT2-P1-C6-T1 00:21:5e:a9:50:42 /lhea@200000000000000/ethernet@200000000000003  physical



*****
FILES
*****


/opt/xcat/bin/getmacs


********
SEE ALSO
********


makedhcp(8)|makedhcp.8

