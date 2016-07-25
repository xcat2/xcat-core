
############
unregnotif.1
############

.. highlight:: perl


****
NAME
****


\ **unregnotif**\  - unregister a Perl module or a command that was watching for the changes of  the desired xCAT database tables.


********
SYNOPSIS
********


\ **unregnotif [-h| -**\ **-help]**\ 

\ **unregnotif [-v| -**\ **-version]**\ 

\ **unregnotif**\  \ *filename*\ 


***********
DESCRIPTION
***********


This command is used to unregistered a Perl module or a command that was watching for the changes of the desired xCAT database tables.


**********
PARAMETERS
**********


\ *filename*\  is the path name of the Perl module or command to be registered.


*******
OPTIONS
*******


\ **-h | -help**\           Display usage message.

\ **-v | -version**\       Command Version.

\ **-V | -verbose**\        Verbose output.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To unregistered a Perl module, enter:


.. code-block:: perl

   unregnotif /opt/xcat/lib/perl/xCAT_monitoring/mycode.pm


2. To register a command, enter:


.. code-block:: perl

   unregnotif /usr/bin/mycmd



*****
FILES
*****


/opt/xcat/bin/unregnotif


********
SEE ALSO
********


regnotif(1)|regnotif.1

