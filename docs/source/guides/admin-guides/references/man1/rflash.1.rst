
########
rflash.1
########

.. highlight:: perl


****
Name
****


\ **rflash**\  - Performs Licensed Internal Code (LIC) update or firmware update on supported xCAT managed nodes.


****************
\ **Synopsis**\ 
****************


\ **rflash**\  [\ **-h | -**\ **-help**\  | \ **-v | -**\ **-version**\ ]

PPC (with HMC) specific:
========================


\ **rflash**\  \ *noderange*\  \ **-p**\  \ *directory*\  [\ **-**\ **-activate**\  {\ **concurrent | disruptive**\ }] [\ **-V | -**\ **-verbose**\ ]

\ **rflash**\  \ *noderange*\  {\ **-**\ **-commit | -**\ **-recover**\ } [\ **-V | -**\ **-verbose**\ ]


PPC (without HMC, using Direct FSP Management) specific:
========================================================


\ **rflash**\  \ *noderange*\  \ **-p**\  \ *directory*\  [\ **-**\ **-activate**\  {\ **disruptive | deferred**\ }] [\ **-d**\  \ *data_directory*\ ]

\ **rflash**\  \ *noderange*\  {\ **-**\ **-commit | -**\ **-recover**\ }


NeXtScale FPC specific:
=======================


\ **rflash**\  \ *noderange*\  \ *http_directory*\ 


OpenPOWER BMC specific (using IPMI):
====================================


\ **rflash**\  \ *noderange*\  [\ *hpm_file_path*\  | \ **-d**\  \ *data_directory*\ ] [\ **-c | -**\ **-check**\ ] [\ **-**\ **-retry=**\ \ *count*\ ] [\ **-V**\ ]

\ **rflash**\  \ *noderange*\  \ **-**\ **-recover**\  \ *bmc_file_path*\ 


OpenPOWER OpenBMC specific :
============================


\ **rflash**\  \ *noderange*\  {[\ **-c | -**\ **-check**\ ] | [\ **-l | -**\ **-list**\ ]}

\ **rflash**\  \ *noderange*\  \ *tar_file_path*\  {[\ **-c | -**\ **-check**\ ] | [\ **-a | -**\ **-activate**\ ] | [\ **-u | -**\ **-upload**\ ]}

\ **rflash**\  \ *noderange*\  \ *image_id*\  {[\ **-a | -**\ **-activate**\ ] | [\ **-d | -**\ **-delete**\ ]}



*******************
\ **Description**\ 
*******************


The \ **rflash**\  command initiates Firmware updates on supported xCAT nodes.  Licensed Internal Code (also known as microcode) updates are performed on supported HMC-attached  POWER5 and POWER6 pSeries nodes, and POWER7 systems using Direct FSP management.

The command scans the specified directory structure for Firmware update package files applicable to the given nodes and components. And then it will \ **automatically**\  select the \ **latest**\  version for the upgrade. The firmware update files include the Microcode update package and associated XML file. They can be downloaded from the IBM Web site: \ *http://www-933.ibm.com/support/fixcentral/*\ .

The POWER5  and POWER6 systems contain several components that use Licensed Internal Code.  The \ **rflash**\  command supports two of these components: the managed system (also known as the Central Electronics Complex, or CEC) and the power subsystem (also known as the Bulk Power Assembly (BPA) or Bulk Power Controller (BPC)).  Some POWER5 managed systems can be attached to a power subsystem.  These power subsystems can support multiple managed systems.  When the \ **rflash**\  command is invoked, xCAT will determine the managed system or power subsystem associated with that CEC and perform the update.

The \ *noderange*\  can be an CEC or CEC list, a Lpar or Lpar list and a Frame or Frame list. But CEC (or Lpar) and Frame \ **can't**\  be used at the same time. When the \ *noderange*\  is an CEC or CEC list, \ **rflash**\  will upgrade the firmware of the CEC or CECs in the cec list. If \ *noderange*\  is a Lpar or Lpar list, \ **rflash**\  will update Licensed Internal Code (LIC) on  HMC-attached POWER5 and POWER6 pSeries nodes, and POWER7 systems using Direct FSP management.  If \ *noderange*\  is a Frame or Frame list, \ **rflash**\  will update Licensed Internal Code (LIC) of the power subsystem on  HMC-attached POWER5 and POWER6 pSeries nodes. The \ *noderange*\  can also be the specified node groups. You  can  specify a  comma or space-separated list of node group ranges. See the \ *noderange*\   man  page  for  detailed usage information.

The command will update firmware for NeXtScale FPC when given an FPC node and the http information needed to access the firmware.

PPC (with HMC) specific:
========================


The \ **rflash**\  command uses the \ **xdsh**\  command to connect to the HMC controlling the given managed system and perform the updates. Before running \ **rflash**\ , use \ **rspconfig**\  to check if the related HMC ssh is enabled. To enable a HMC ssh connection, use \ **rspconfig**\  command.

\ **Warning!**\   This command may take considerable time to complete, depending on the number of systems being updated and the workload on the target HMC.  In particular, power subsystem updates may take an hour or more if there are many attached managed systems.

Depending on the Licensed Internal Code update that is installed, the affected HMC-attached POWER5 and POWER6 systems may need to be recycled.  The \ **-**\ **-activate**\  flag determines how the affected systems activate the new code.  The concurrent option activates code updates that do not require a system recycle (known as a "concurrent update").  If this option is given with an update that requires a system recycle (known as a "disruptive update"), a message will be returned, and no activation will be performed.  The disruptive option will cause any affected systems that are powered on to be powered down before installing and activating the update.  Once the update is complete, the command will attempt to power on any affected systems that it powered down.  Those systems that were powered down when the command was issued will remain powered down when the update is complete.

The flash chip of a POWER5 and POWER6 managed system or power subsystem stores firmware in two locations, referred to as the temporary side and the permanent side.  By default, most POWER5 and POWER6 systems boot from the temporary side of the flash.  When the \ **rflash**\  command updates code, the current contents of the temporary side are written to the permanent side, and the new code is written to the temporary side.  The new code is then activated.  Therefore, the two sides of the flash will contain different levels of code when the update has completed.

The \ **-**\ **-commit**\  flag is used to write the contents of the temporary side of the flash to the permanent side.  This flag should be used after updating code and verifying correct system operation.  The \ **-**\ **-recover**\  flag is used to write the permanent side of the flash chip back to the temporary side.  This flag should be used to recover from a corrupt flash operation, so that the previously running code can be restored.

\ **NOTE:**\ When the \ **-**\ **-commit**\  or \ **-**\ **-recover**\  two flags is used, the noderange \ **cannot**\  be BPA. It only \ **can**\  be CEC or LPAR, and  will take effect for \ **both**\  managed systems and power subsystems.

xCAT recommends that you shutdown your Operating System images and power off your managed systems before applying disruptive updates to managed systems or power subsystems.

Any previously activated code on the affected systems will be automatically accepted into permanent flash by this procedure.

\ **IMPORTANT!**\   If the power subsystem is recycled, all of its attached managed systems will be recycled.

If it outputs \ **"Timeout waiting for prompt"**\  during the upgrade, set the \ **"ppctimeout"**\  larger in the \ **site**\  table. After the upgrade, remeber to change it back. If run the \ **"rflash"**\  command on an AIX management node, need to make sure the value of \ **"useSSHonAIX"**\  is \ **"yes"**\  in the site table.


PPC (using Direct FSP Management) specific:
===========================================


In currently Direct FSP/BPA Management, our \ **rflash**\  doesn't support \ **concurrent**\  value of \ **-**\ **-activate**\  flag, and supports \ **disruptive**\  and \ **deferred**\ . The \ **disruptive**\  option will cause any affected systems that are powered on to be powered down before installing and activating the update. So we require that the systems should be powered off before do the firmware update.

The \ **deferred**\  option will load the new firmware into the T (temp) side, but will not activate it like the disruptive firmware. The customer will continue to run the Frames and CECs working with the P (perm) side and can wait for a maintenance window where they can activate and boot the Frame/CECs with new firmware levels. Refer to the doc to get more details: XCAT_Power_775_Hardware_Management

In Direct FSP/BPA Management, there is \ **-d**\  \ *data_directory*\  option. The default value is /tmp. When doing firmware update, \ **rflash**\  will put some related data from rpm packages in <data_directory> directory, so the execution of \ **rflash**\  will require available disk space in <data_directory> for the command to properly execute:

For one GFW rpm package and one power code rpm package, if the GFW rpm package size is gfw_rpmsize, and the Power code rpm package size is power_rpmsize, it requires that the available disk space should be more than: 1.5\*gfw_rpmsize + 1.5\*power_rpmsize

For Power 775, the \ **rflash**\  command takes effect on the primary and secondary FSPs or BPAs almost in parallel.

For more details about the Firmware Update using Direct FSP/BPA Management, refer to: XCAT_Power_775_Hardware_Management#Updating_the_BPA_and_FSP_firmware_using_xCAT_DFM


NeXtScale FPC specific:
=======================


The command will update firmware for NeXtScale FPC when given an FPC node and the http information needed to access the firmware. The http information required includes both the MN IP address as well as the directory containing the firmware. It is recommended that the firmware be downloaded and placed in the /install directory structure as the xCAT MN /install directory is configured with the correct permissions for http.  Refer to the doc to get more details: XCAT_NeXtScale_Clusters


OpenPOWER specific (using IPMI):
================================


The command will update firmware for OpenPOWER BMC when given an OpenPOWER node and either the hpm formatted file path or path to a data directory.
\ **Note:**\  When using \ **rflash**\  in hierarchical environment, the hpm file or data directory must be accessible from Service Nodes.


OpenPOWER OpenBMC specific:
===========================


The command will update firmware for OpenPOWER OpenBMC when given an OpenPOWER node and either an update .tar file or an uploaded image id.
\ **Note:**\  When using \ **rflash**\  in hierarchical environment, the .tar file must be accessible from Service Nodes.



***************
\ **Options**\ 
***************



\ **-h|-**\ **-help**\ 
 
 Writes the command's usage statement to standard output.
 


\ **-c|-**\ **-check**\ 
 
 Check the firmware version of BMC and an update file.
 


\ **-p**\  \ *directory*\ 
 
 Specifies the directory where the packages are located.
 


\ **-d**\  \ *data_directory*\ 
 
 PPC (without HMC, using Direct FSP Management) specific:
 
 Specifies the directory where the raw data from rpm packages for each CEC/Frame are located. The default directory is /tmp. The option is only used in Direct FSP/BPA Management.
 
 OpenPOWER BMC specific (using IPMI):
 
 Used for IBM Power S822LC for Big Data systems only. Specifies the directory where the \ **pUpdate**\  utility and at least one of BMC or PNOR update files are located. The utility and update files can be downloaded from FixCentral.
 


\ **-**\ **-activate**\  {\ **concurrent**\  | \ **disruptive**\ }
 
 Must be specified to activate the new Licensed Internal Code.  The "disruptive" option will cause the target systems to be recycled.  Without this flag, LIC updates will be installed only, not activated.
 


\ **-**\ **-commit**\ 
 
 Used to commit the flash image in the temporary side of the chip to the permanent side for both managed systems and power subsystems.
 


\ **-**\ **-recover**\ 
 
 PPC (with HMC) and PPC (without HMC, using Direct FSP Management) specific:
 
 Used to recover the flash image in the permanent side of the chip to the temporary side for both managed systems and power subsystems.
 
 OpenPOWER BMC specific (using IPMI):
 
 Used for IBM Power S822LC for Big Data systems only. Used to recover the BMC with a BMC image downloaded from FixCentral.
 


\ **-**\ **-retry=**\ \ *count*\ 
 
 Specify number of times to retry the update if failure is detected. Default value is 2. Value of 0 can be used to indicate no retries.
 


\ **-a|-**\ **-activate**\ 
 
 Activate update image. Image id or update file must be specified.
 


\ **-l|-**\ **-list**\ 
 
 List currently uploaded update images. "(\*)" indicates currently active image.
 


\ **-u|-**\ **-upload**\ 
 
 Upload update image. Specified file must be in .tar format.
 


\ **-d|-**\ **-delete**\ 
 
 Delete update image from BMC
 


\ **-v|-**\ **-version**\ 
 
 Displays the command's version.
 


\ **-V|-**\ **-verbose**\ 
 
 Verbose output.
 



*******************
\ **Exit Status**\ 
*******************


0 The command completed successfully.

1 An error has occurred.


****************
\ **Examples**\ 
****************



1. To update  only the  power subsystem attached to a single HMC-attached pSeries CEC(cec_name), and recycle the power  subsystem  and  all attached managed systems when the update is complete, and the Microcode update package and associated XML file are in /tmp/fw, enter:
 
 
 .. code-block:: perl
 
   rflash cec_name -p /tmp/fw --activate disruptive
 
 


2. To update  only the  power subsystem attached to a single HMC-attached pSeries node, and recycle the power  subsystem  and  all attached managed systems when the update is complete, and the Microcode update package and associated XML file are in /tmp/fw, enter:
 
 
 .. code-block:: perl
 
   rflash bpa_name -p /tmp/fw --activate disruptive
 
 


3. To commit a firmware update to permanent flash for both managed system and the related power subsystems, enter:
 
 
 .. code-block:: perl
 
   rflash cec_name --commit
 
 


4. To update the firmware on a NeXtScale FPC specify the FPC node name and the HTTP location of the file including the xCAT MN IP address and the directory on the xCAT MN containing the firmware as follows:
 
 
 .. code-block:: perl
 
   rflash fpc01 http://10.1.147.169/install/firmware/fhet17a/ibm_fw_fpc_fhet17a-2.02_anyos_noarch.rom
 
 


5. To update the firmware on OpenPOWER machine specify the node name and the file path of the HPM firmware file as follows:
 
 
 .. code-block:: perl
 
   rflash fs3 /firmware/8335_810.1543.20151021b_update.hpm
 
 
 Print verbose message to rflash log file (/var/log/xcat/rflash/fs3.log) when updading firmware:
 
 
 .. code-block:: perl
 
   rflash fs3 /firmware/8335_810.1543.20151021b_update.hpm -V
 
 


6. To update the firmware on IBM Power S822LC for Big Data machine specify the node name and the file path of the data directory containing pUpdate utility and BMC and/or PNOR update files:
 
 
 .. code-block:: perl
 
   rflash briggs01 -d /root/supermicro/OP825
 
 


7. To update the firmware on the OpenBMC machine, specify the firmare update file to upload and activate:
 
 
 .. code-block:: perl
 
    rflash p9euh02 -a /tmp/witherspoon.pnor.squashfs.tar
 
 



****************
\ **Location**\ 
****************


\ **/opt/xcat/bin/rflash**\ 


*****
NOTES
*****


This command is part of the xCAT software product.


********
SEE ALSO
********


rinv(1)|rinv.1, rspconfig(1)|rspconfig.1

