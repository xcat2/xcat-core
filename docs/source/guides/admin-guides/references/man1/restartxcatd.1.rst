
##############
restartxcatd.1
##############

.. highlight:: perl


****
NAME
****


\ **restartxcatd**\  - Restart the xCAT daemon (xcatd).


********
SYNOPSIS
********


\ **restartxcatd**\  [[\ **-h | -**\ **-help**\ ] | [\ **-v | -**\ **-version**\ ] | [\ **-r | -**\ **-reload**\ ]] [\ **-V | -**\ **-verbose**\ ]


***********
DESCRIPTION
***********


The \ **restartxcatd**\  command restarts the xCAT daemon (xcatd).

\ **Linux Specific**\ 


It will perform the xcatd \ *fast restart*\ . The xcatd \ *fast restart*\  is a specific restart which has two advantages compares to the \ *stop*\  and then \ *start*\ .
    1. The interval of xcatd out of service is very short.
    2. The in processing request which initiated by old xcatd will not be stopped by force. The old xcatd will hand over the sockets to new xcatd, but old xcat will still be waiting for the in processing request to finish before the exit.

It does the same thing as 'service xcatd restart' on NON-systemd enabled Operating System like rh6.x and sles11.x. But for the systemd enabled Operating System like rh7 and sles12, the 'service xcatd restart' just do the \ *stop*\  and \ *start*\  instead of xcatd \ *fast restart*\ .

It's recommended to use \ **restartxcatd**\  command to restart xcatd on systemd enable system like rh7 and sles12 instead of 'service xcatd restart' or 'systemctl restart xcatd'.

\ **AIX Specific**\ 


It runs 'stopsrc -s xcatd' to stop xcatd first if xcatd is active, then runs 'startsrc -s xcatd' to start xcatd.

If the xcatd subsystem was not created, \ **restartxcatd**\  will create it automatically.


*******
OPTIONS
*******


\ **-h|-**\ **-help**\           Display usage message.

\ **-v|-**\ **-version**\        Command Version.

\ **-r|-**\ **-reload**\         On a Service Node, services will not be restarted.

\ **-V|-**\ **-verbose**\        Display the verbose messages.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To restart the xCAT daemon, enter:


.. code-block:: perl

  restartxcatd



*****
FILES
*****


/opt/xcat/sbin/restartxcatd

