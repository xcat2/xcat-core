
##########
xcatsnap.8
##########

.. highlight:: perl


****
NAME
****


\ **xcatsnap**\  - Gathers information for service about the current running xCAT environment.


********
SYNOPSIS
********


\ **xcatsnap**\ 

\ **xcatsnap**\  [\ **-h | -**\ **-help**\ ]

\ **xcatsnap**\  [\ **-v | -**\ **-version**\ ]

\ **xcatsnap**\  [\ **-B | -**\ **-bypass**\ ]

\ **xcatsnap**\  [\ **-d | -**\ **-dir**\ ]


***********
DESCRIPTION
***********


\ **xcatsnap**\  -  The xcatsnap command gathers configuration, log and trace information about the xCAT components that are installed. This command only collects the data on the local node on which this command is run. This command is typically executed when a problem is encountered with any of these components in order to provide service information to the IBM Support Center.

This command should only be executed at the instruction of the IBM Support Center.


*******
OPTIONS
*******



\ **-h|-**\ **-help**\ 
 
 Displays the usage message.
 


\ **-v|-**\ **-version**\ 
 
 Displays the release version of the code.
 


\ **-B|-**\ **-bypass**\ 
 
 Runs in bypass mode, use if the xcatd daemon is hung.
 


\ **-d|-**\ **-dir**\ 
 
 The directory to put the snap information.  Default is /tmp/xcatsnap.
 



*********************
ENVIRONMENT VARIABLES
*********************



********
EXAMPLES
********



1. Run the xcatsnap routine in bypass mode and put info in /tmp/mydir :
 
 
 .. code-block:: perl
 
   xcatsnap -B -d /tmp/mydir
 
 


2.  To run the xcatsnap routine and use default directory /tmp/xcatsnap :
 
 
 .. code-block:: perl
 
   xcatsnap
 
 


