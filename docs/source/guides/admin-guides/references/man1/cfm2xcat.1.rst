
##########
cfm2xcat.1
##########

.. highlight:: perl


****
NAME
****


\ **cfm2xcat**\  - Migrates the CFM setup in CSM to the xdcp rsync setup in xCAT.


****************
\ **SYNOPSIS**\ 
****************


\ **cfm2xcat**\  [\ **-i**\  \ *path of the CFM distribution files generated*\ ] [\ **-o**\  \ *path of the xdcp rsync files generated from the CFM distribution files*\ ]

\ **cfm2xcat**\  [\ **-h**\ ]


*******************
\ **DESCRIPTION**\ 
*******************


Copy the cfm2xcat command to the CSM Management Server.  Run the command, indicating where you want your files saved with the -i and -o flags. They can be in the same directory.

The cfm2xcat command will run cfmupdatenode -a, saving the generated CFM distribution files in the directory indicates with (-i). From those distribution files, it will generate xdcp rsync input files (-F option on xdcp) in the directory indicated by ( -o).

Check the rsync files generated.  There will be a file generated (rsyncfiles)  from the input -o option on the command, and the same file with a (.nr) extension generated for each different noderange that will used to sync files based on your CFM setup in CSM. The rsyncfiles will contain the rsync file list.   The rsyncfiles.nr will contain the noderange. If multiple noderanges then the file name (rsyncfiles)  will be appended with a number.


*******
OPTIONS
*******


\ **-h**\           Display usage message.

\ **-i**\           Path of the CFM distribution files generated from the cfmupdatenode -a command.

\ **-o**\           Path of the xdcp rsync input file generated from the CFM distribution files.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To build xCAT rsync files to use with xdcp -F , enter on the CSM Management Server, make sure the path exists:


.. code-block:: perl

  cfm2xcat -i /tmp/cfm/cfmdistfiles -o /tmp/cfm/rsyncfiles


2. To use the file on the xCAT Management Node copy to /tmp/cfm on the xCAT MN:


.. code-block:: perl

  xdcp ^/tmp/cfm/rsyncfiles.nr -F /tmp/cfm/rsyncfiles
  xdcp ^/tmp/cfm/rsyncfiles.nr1 -F /tmp/cfm/rsyncfiles1
  xdcp ^/tmp/cfm/rsyncfiles.nr2 -F /tmp/cfm/rsyncfiles2



*****
FILES
*****


/opt/xcat/share/xcat/tools/cfm2xcat

