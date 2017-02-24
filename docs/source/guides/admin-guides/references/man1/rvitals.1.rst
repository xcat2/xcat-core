
#########
rvitals.1
#########

.. highlight:: perl


****
Name
****


\ **rvitals**\  - remote hardware vitals


****************
\ **Synopsis**\ 
****************


\ **rvitals**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]

FSP/LPAR (with HMC) specific:
=============================


\ **rvitals**\  \ *noderange*\  {\ **temp | voltage | lcds | all**\ }


CEC/LPAR/Frame (using Direct FSP Management) specific:
======================================================


\ **rvitals**\  \ *noderange*\  {\ **rackenv | lcds | all**\ } [\ **-V**\ | \ **-**\ **-verbose**\ ]


MPA specific:
=============


\ **rvitals**\  \ *noderange*\  {\ **temp | voltage | wattage | fanspeed | power | leds | summary | all**\ }


Blade specific:
===============


\ **rvitals**\  \ *noderange*\  {\ **temp | wattage | fanspeed | leds | summary | all**\ }


BMC specific:
=============


\ **rvitals**\  \ *noderange*\  {\ **temp | voltage | wattage | fanspeed | power | leds | all**\ }


OpenPOWER server specific:
==========================


\ **rvitals**\  \ *noderange*\  {\ **temp | voltage | wattage | fanspeed | power | leds | all**\ }



*******************
\ **Description**\ 
*******************


\ **rvitals**\   retrieves hardware vital information from the on-board Service
Processor for a single or range of nodes and groups.


***************
\ **Options**\ 
***************



\ **cputemp**\ 
 
 Retrieves CPU temperatures.
 


\ **disktemp**\ 
 
 Retrieves HD back plane temperatures.
 


\ **ambtemp**\ 
 
 Retrieves ambient temperatures.
 


\ **temp**\ 
 
 Retrieves all temperatures.
 


\ **voltage**\ 
 
 Retrieves power supply and VRM voltage readings.
 


\ **fanspeed**\ 
 
 Retrieves fan speeds.
 


\ **lcds**\ 
 
 Retrieves LCDs status.
 


\ **rackenv**\ 
 
 Retrieves rack environmentals.
 


\ **leds**\ 
 
 Retrieves LEDs status.
 


\ **power**\ 
 
 Retrieves power status.
 


\ **powertime**\ 
 
 Retrieves total power uptime.  This value only increases, unless
 the Service Processor flash gets updated.  This option is not valid
 for x86 architecture systems.
 


\ **reboot**\ 
 
 Retrieves  total  number of reboots.  This value only increases,
 unless the Service Processor flash gets updated.  This option
 is not valid for x86 architecture systems.
 


\ **state**\ 
 
 Retrieves the system state.
 


\ **all**\ 
 
 All of the above.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



****************
\ **Examples**\ 
****************



.. code-block:: perl

  rvitals node5 all


Output is similar to:


.. code-block:: perl

  node5: CPU 1 Temperature: + 29.00 C (+ 84.2 F)
  node5: CPU 2 Temperature: + 19.00 C (+ 66.2 F)
  node5: DASD Sensor 1 Temperature: + 32.00 C (+ 89.6 F)
  node5: System Ambient Temperature Temperature: + 26.00 C (+ 78.8 F)
  node5: +5V Voltage: +  5.01V
  node5: +3V Voltage: +  3.29V
  node5: +12V Voltage: + 11.98V
  node5: +2.5V Voltage: +  2.52V
  node5: VRM1 Voltage: +  1.61V
  node5: VRM2 Voltage: +  1.61V
  node5: Fan 1 Percent of max:   100%
  node5: Fan 2 Percent of max:   100%
  node5: Fan 3 Percent of max:   100%
  node5: Fan 4 Percent of max:   100%
  node5: Fan 5 Percent of max:   100%
  node5: Fan 6 Percent of max:   100%
  node5: Current Power Status On
  node5: Current LCD1: SuSE Linux
  node5: Power On Seconds  11855915
  node5: Number of Reboots   930
  node5: System State Booting OS or in unsupported OS



****************
\ **SEE ALSO**\ 
****************


rpower(1)|rpower.1, rinv(1)|rinv.1

