
#######
lsslp.1
#######

.. highlight:: perl


****
NAME
****


\ **lsslp**\  - Discovers selected networked services information within the same subnet.


********
SYNOPSIS
********


\ **lsslp [-h| -**\ **-help]**\ 

\ **lsslp [-v| -**\ **-version]**\ 

\ **lsslp**\  [\ *noderange*\ ] [\ **-V**\ ] [\ **-i**\  \ *ip[,ip..]*\ ] \ **[-w] [-r|-x|-z] [-n] [-s CEC|FRAME|MM|IVM|RSA|HMC|CMM|IMM2|FSP]**\  [\ **-t**\  \ *tries*\ ] [\ **-I**\ ] [\ **-C**\  \ *counts*\ ] [\ **-T**\  \ *timeout*\ ] [\ **-**\ **-vpdtable**\ ]


***********
DESCRIPTION
***********


The lsslp command discovers selected service types using the -s flag. All service types are returned if the -s flag is not specified. If a specific IP address is not specified using the -i flag, the request is sent out all available network adapters. The optional -r, -x, -z and --vpdtable flags format the output. If you can't receive all the hardware, use -T to increase the waiting time.

NOTE: SLP broadcast requests will propagate only within the subnet of the network adapter broadcast IPs specified by the -i flag.


*******
OPTIONS
*******


\ **noderange**\    The nodes which the user want to discover.  If the user specify the noderange, lsslp will just return the nodes in the node range. Which means it will help to add the new nodes to the xCAT database without modifying the existed definitions. But the nodes' name specified in noderange should be defined in database in advance. The specified nodes' type can be frame/cec/hmc/fsp/bpa. If the it is frame or cec, lsslp will list the bpa or fsp nodes within the nodes(bap for frame, fsp for cec).  Do not use noderange with the flag -s.

\ **-i**\           IP(s) the command will send out (defaults to all available adapters).

\ **-h**\           Display usage message.

\ **-n**\           Only display and write the newly discovered hardwares.

\ **-u**\           Do unicast to a specified IP range. Must be used with \ **-s**\  and \ **-**\ **-range**\ . The \ **-u**\  flag is not supported on AIX.

\ **-**\ **-range**\      Specify one or more IP ranges. Must be use in unicast mode. It accepts multiple formats. For example, 192.168.1.1/24, 40-41.1-2.3-4.1-100. If the range is huge, for example, 192.168.1.1/8, lsslp may take a very long time for node scan. So the range should be exactly specified.

\ **-r**\           Display Raw SLP response.

\ **-C**\           The number of the expected responses specified by the user.  When using this flag, lsslp will not return until the it has found all the nodes or time out.  The default max time is 3 secondes. The user can use -T flag the specify the time they want to use.  A short time will limite the time costing, while a long time will help to find all the nodes.

\ **-T**\           The number in seconds to limite the time costing of lsslp.

\ **-s**\           Service type interested in discovering.

\ **-t**\           Number or service-request attempts.

\ **-**\ **-vpdtable**\   Output the SLP response in vpdtable formatting. Easy for writting data to vpd table.

\ **-v**\           Command Version.

\ **-V**\           Verbose output.

\ **-w**\           Writes output to xCAT database.

\ **-x**\           XML format.

\ **-z**\           Stanza formated output.

\ **-I**\           Give the warning message for the nodes in database which have no SLP responses. Note that this flag noly can be used after the database migration finished successfully.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To list all discovered HMC service types in tabular format, enter:


.. code-block:: perl

  lsslp -s HMC


Output is similar to:


.. code-block:: perl

  device type-model serial-number ip-addresses   hostname
  HMC    7310CR2    103F55A        1.1.1.115      hmc01
  HMC    7310CR2    105369A        3.3.3.103      hmc02
  HMC    7310CR3    KPHHK24        3.3.3.154      hmc03


2. list all discovered FSP service types in raw response format on subnet 30.0.0.255, enter:


.. code-block:: perl

  lsslp -i 3.0.0.255 -s CEC -r


Output is similar to:


.. code-block:: perl

  (type=cec-service-processor),(serial-number=10A3AEB),(machinetype-model=9117-570),(fru-serial-number=YL11C5338102),(hostname=),(frame-number=0),(cage-number=0),(ip-address=3.0.0.94,1.1.1.147),(web-url=https://3.0.0.94:473 ), (slot=1),(bpc-machinetype-model=0),(bpc-serial-number=0),(Image=fips240/b0630a_0623.240)
  (type=cec-service-processor),(serial-number=10A3E2B),(machinetype-model=9117-570),(fru-serial- number=YL11C5338250),(hostname=),(frame-number=0),(cage-number=0),(ip-address=3.0.0.95,1.1.1.147), (web-url=https://3.0.0.95:473 ),(slot=1),(bpc-machinetype-model=0),(bpc-serial-number=0),(Image=fips240/b0630a_0623.240)


3. To list all discovered MM service types in XML format and write the output to the xCAT database, enter:


.. code-block:: perl

  lsslp -s MM -x -w


Output is similar to:


.. code-block:: perl

   <Node>
     <groups>mm,all</groups>
     <id>00:14:5E:E0:CB:1E</id>
     <mgt>blade</mgt>
     <mtm>029310C</mtm>
     <node>Server-029310C-SN100485A-A</node>
     <nodetype>mm</nodetype>
     <otherinterfaces>9.114.47.229</otherinterfaces>
     <serial>100485A</serial>
   </Node>


4. To list all discovered service types in stanza format and write the output to the xCAT database, enter:


.. code-block:: perl

  lsslp -z -w


Output is similar to:


.. code-block:: perl

  c76v1hmc02:
         objtype=node
         hcp=c76v1hmc02
         nodetype=hmc
         mtm=7315CR2
         serial=10407DA
         ip=192.168.200.125
         groups=hmc,all
         mgt=hmc
         mac=00:1a:64:fb:7d:50        
         hidden=0
  192.168.200.244:
         objtype=node
         hcp=192.168.200.244
         nodetype=fsp
         mtm=9125-F2A
         serial=0262662
         side=A-0
         otherinterfaces=192.168.200.244
         groups=fsp,all
         mgt=fsp
         id=4
         parent=Server-9125-F2A-SN0262662
         mac=00:1a:64:fa:01:fe
         hidden=1
  Server-8205-E6B-SN1074CDP:
         objtype=node
         hcp=Server-8205-E6B-SN1074CDP
         nodetype=cec
         mtm=8205-E6B
         serial=1074CDP
         groups=cec,all
         mgt=fsp
         id=0
         hidden=0
  192.168.200.33:
         objtype=node
         hcp=192.168.200.33
         nodetype=bpa
         mtm=9458-100
         serial=99201WM
         side=B-0
         otherinterfaces=192.168.200.33
         groups=bpa,all
         mgt=bpa
         id=0
         mac=00:09:6b:ad:19:90
         hidden=1
  Server-9125-F2A-SN0262652:
         objtype=node
         hcp=Server-9125-F2A-SN0262652
         nodetype=frame
         mtm=9125-F2A
         serial=0262652
         groups=frame,all
         mgt=fsp
         id=5
         hidden=0


5. To list all discovered service types in stanza format and display the IP address, enter:


.. code-block:: perl

  lsslp -w


Output is similar to:


.. code-block:: perl

  mm01:
     objtype=node
     nodetype=fsp
     mtm=8233-E8B
     serial=1000ECP
     side=A-0
     groups=fsp,all
     mgt=fsp
     id=0
     mac=00:14:5E:F0:5C:FD
     otherinterfaces=50.0.0.5
 
  bpa01:
     objtype=node
     nodetype=bpa
     mtm=9A01-100
     serial=0P1N746
     side=A-1
     groups=bpa,all
     mgt=bpa
     id=0
     mac=00:1A:64:54:8C:A5
     otherinterfaces=50.0.0.1


6. To list all the CECs, enter:


.. code-block:: perl

  lsslp -s CEC 
  
  device  type-model  serial-number  side  ip-addresses  hostname
  FSP     9117-MMB    105EBEP        A-1   20.0.0.138    20.0.0.138
  FSP     9117-MMB    105EBEP        B-1   20.0.0.139    20.0.0.139
  CEC     9117-MMB    105EBEP                            Server-9117-MMB-SN105EBEP


7. To list all the nodes defined in database which have no SLP response.


.. code-block:: perl

   lsslp -I


Output is similar to:


.. code-block:: perl

  These nodes defined in database but can't be discovered: f17c00bpcb_b,f17c01bpcb_a,f17c01bpcb_b,f17c02bpcb_a,
 
  device  type-model  serial-number  side  ip-addresses  hostname
  bpa     9458-100    BPCF017        A-0   40.17.0.1     f17c00bpca_a
  bpa     9458-100    BPCF017        B-0   40.17.0.2     f17c00bpcb_a


8. To find the nodes within the user specified. Make sure the noderange input have been defined in xCAT database.


.. code-block:: perl

    lsslp CEC1-CEC3
 or lsslp CEC1,CEC2,CEC3
 
   device  type-model  serial-number  side  ip-addresses     hostname
   FSP     9A01-100    0P1P336        A-0   192.168.200.34  192.168.200.34
   FSP     9A01-100    0P1P336        B-0   192.168.200.35  192.168.200.35
   FSP     9A01-100    0P1P336        A-1   50.0.0.27       50.0.0.27
   FSP     9A01-100    0P1P336        B-1   50.0.0.28       50.0.0.28
   CEC     9A01-100    0P1P336                              CEC1
   FSP     8233-E8B    1040C7P        A-0   192.168.200.36  192.168.200.36
   FSP     8233-E8B    1040C7P        B-0   192.168.200.37  192.168.200.37
   FSP     8233-E8B    1040C7P        A-1   50.0.0.29       50.0.0.29
   FSP     8233-E8B    1040C7P        B-1   50.0.0.30       50.0.0.30
   CEC     8233-E8B    1040C7P                              CEC2
   FSP     8205-E6B    1000ECP        A-0   192.168.200.38  192.168.200.38
   FSP     8205-E6B    1000ECP        B-0   192.168.200.39  192.168.200.39
   FSP     8205-E6B    1000ECP        A-1   50.0.0.31       50.0.0.27
   FSP     8205-E6B    1000ECP        B-1   50.0.0.32       50.0.0.28
   CEC     8205-E6B    1000ECP                              CEC3


9. To list all discovered CMM in stanza format, enter:
   lsslp -s CMM -m -z


.. code-block:: perl

  e114ngmm1:
         objtype=node
         mpa=e114ngmm1
         nodetype=cmm
         mtm=98939AX
         serial=102537A
         groups=cmm,all
         mgt=blade
         hidden=0
         otherinterfaces=70.0.0.30
         hwtype=cmm


10. To use lsslp unicast, enter:


.. code-block:: perl

     lsslp -u -s CEC --range 40-41.1-2.1-2.1-2



*****
FILES
*****


/opt/xcat/bin/lsslp


********
SEE ALSO
********


rscan(1)|rscan.1

