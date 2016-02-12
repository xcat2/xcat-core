
############
rollupdate.1
############

.. highlight:: perl


****
NAME
****


\ **rollupdate**\  - performs cluster rolling update


********
SYNOPSIS
********


\ **cat**\  \ *stanza-file*\  \ **|**\  \ **rollupdate**\  [\ **-V**\  | \ **-**\ **-verbose**\ ] [\ **-t**\ | \ **-**\ **-test**\ ]

\ **rollupdate**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **rollupdate**\  command creates and submits scheduler reservation jobs that will notify xCAT to shutdown a group of nodes, run optional out-of-band commands from the xCAT management node, and reboot the nodes.  Currently, only LoadLeveler is supported as a job scheduler with \ **rollupdate**\ .

Input to the \ **rollupdate**\  command is passed in as stanza data through STDIN.  Information such as the sets of nodes that will be updated, the name of the job scheduler, a template for generating job command files, and other control data are required.  See 
/opt/xcat/share/xcat/rollupdate/rollupdate.input.sample 
and
/opt/xcat/share/xcat/rollupdate/rollupdate_all.input.sample 
for stanza keywords, usage, and examples.

The \ **rollupdate**\  command will use the input data to determine each set of nodes that will be managed together as an update group.  For each update group, a job scheduler command file is created and a reservation request is submitted.  When the group of nodes becomes available and the scheduler activates the reservation, the xcatd daemon on the management node will be notified to begin the update process for all the nodes in the update group.  If specified, prescripts will be run, an operating system shutdown command will be sent to each node, out-of-band operations can be run on the management node, and the nodes are powered back on.

The \ **rollupdate**\  command assumes that, if the update is to include rebooting stateless or statelite nodes to a new operating system image, the image has been created and tested, and that all relevant xCAT commands have been run for the nodes such that the new image will be loaded when xCAT reboots the nodes.


*******
OPTIONS
*******



\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-V|-**\ **-verbose**\ 
 
 Display additional progress and error messages.  Output is also logged in /var/log/xcat/rollupdate.log.
 


\ **-t|-**\ **-test**\ 
 
 Run the rollupdate command in test mode only to verify the output files that are created.  No scheduler reservation requests will be submitted.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 



************
RETURN VALUE
************



0 The command completed successfully.



1 An error has occurred.




********
EXAMPLES
********



1.
 
 To run a cluster rolling update based on the information you have created in the file 
 /u/admin/rolling_updates/update_all.stanza
 enter:
 
 
 .. code-block:: perl
 
    cat /u/admin/rolling_updates/update_all.stanza | rollupdate
 
 



*****
FILES
*****


/opt/xcat/bin/rollupdate

/opt/xcat/share/xcat/rollupdate/rollupdate.input.sample

/opt/xcat/share/xcat/rollupdate/ll.tmpl

/opt/xcat/share/xcat/rollupdate/rollupdate_all.input.sample

/opt/xcat/share/xcat/rollupdate/llall.tmpl

/var/log/xcat/rollupdate.log


********
SEE ALSO
********


