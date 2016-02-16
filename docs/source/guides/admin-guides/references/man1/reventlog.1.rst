
###########
reventlog.1
###########

.. highlight:: perl


****
Name
****


\ **reventlog**\  - retrieve or clear remote hardware event logs


****************
\ **Synopsis**\ 
****************


\ **reventlog**\  \ *noderange*\  {\ *number-of-entries*\  [\ **-s**\ ]|\ **all [-s] | clear**\ }

\ **reventlog**\  [\ **-h | -**\ **-help | -v | -**\ **-version**\ ]


*******************
\ **Description**\ 
*******************


\ **reventlog**\   can  display any number of remote hardware event log entries
or clear them for a range of nodes.  Hardware  event
logs are stored on each servers service processor.


***************
\ **Options**\ 
***************



\ *number-of-entries*\ 
 
 Retrieve the specified number of entries from the nodes' service processors.
 


\ **all**\ 
 
 Retrieve all entries.
 


\ **-s**\ 
 
 To sort the entries from latest (always the last entry in event DB) to oldest (always the first entry in event DB). If \ **number-of-entries**\  specified, the latest \ **number-of-entries**\  events will be output in the order of latest to oldest.
 


\ **clear**\ 
 
 Clear event logs.
 


\ **-h | -**\ **-help**\ 
 
 Print help.
 


\ **-v | -**\ **-version**\ 
 
 Print version.
 



****************
\ **Examples**\ 
****************



1.
 
 
 .. code-block:: perl
 
   reventlog node4,node5 5
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node4: SERVPROC I 09/06/00 15:23:33 Remote Login Successful User ID = USERID[00]
   node4: SERVPROC I 09/06/00 15:23:32 System spn1 started a RS485 connection with us[00]
   node4: SERVPROC I 09/06/00 15:22:35 RS485 connection to system spn1 has ended[00]
   node4: SERVPROC I 09/06/00 15:22:32 Remote Login Successful User  ID  = USERID[00]
   node4: SERVPROC I 09/06/00 15:22:31 System spn1 started a RS485 connection with us[00]
   node5: SERVPROC I 09/06/00 15:22:32 Remote Login Successful User  ID  = USERID[00]
   node5: SERVPROC I 09/06/00 15:22:31 System spn1 started a RS485 connection with us[00]
   node5: SERVPROC I 09/06/00 15:21:34 RS485 connection to system spn1 has ended[00]
   node5: SERVPROC I 09/06/00 15:21:30 Remote Login Successful User ID = USERID[00]
   node5: SERVPROC I 09/06/00 15:21:29 System spn1 started a RS485 connection with us[00]
 
 


2.
 
 
 .. code-block:: perl
 
   reventlog node4,node5 clear
 
 
 Output is similar to:
 
 
 .. code-block:: perl
 
   node4: clear
   node5: clear
 
 



********
SEE ALSO
********


rpower(1)|rpower.1, monstart(1)|monstart.1

