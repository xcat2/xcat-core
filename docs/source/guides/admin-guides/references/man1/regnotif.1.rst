
##########
regnotif.1
##########

.. highlight:: perl


****
NAME
****


\ **regnotif**\  - Registers a Perl module or a command that will get called when changes occur in the desired xCAT database tables.


********
SYNOPSIS
********


\ **regnotif [-h| -**\ **-help]**\ 

\ **regnotif  [-v| -**\ **-version]**\ 

\ **regnotif**\  \ *filename tablename[,tablename]...*\  [\ **-o | -**\ **-operation**\  \ *actions*\ ]


***********
DESCRIPTION
***********


This command is used to register a Perl module or a command to the xCAT notification table. Once registered, the module or the command will get called when changes occur in the xCAT database tables indicated by tablename. The changes can be row addition, deletion and update which are specified by actions.


**********
PARAMETERS
**********


\ *filename*\  is the path name of the Perl module or command to be registered.
\ *tablename*\  is the name of the table that the user is interested in.


*******
OPTIONS
*******


\ **-h | -**\ **-help**\           Display usage message.

\ **-v | -**\ **-version**\        Command Version.

\ **-V | -**\ **-verbose**\        Verbose output.

\ **-o | -**\ **-operation**\      specifies the database table actions that the user is interested in. It is a comma separated list. 'a' for row addition, 'd' for row deletion and 'u' for row update.


************
RETURN VALUE
************


0 The command completed successfully.

1 An error has occurred.


********
EXAMPLES
********


1. To register a Perl module that gets invoked when rows get added or deleted.  in the nodelist and the nodehm tables, enter:


.. code-block:: perl

  regnotif /opt/xcat/lib/perl/xCAT_monitoring/mycode.pm nodelist,nodhm -o a,d


2. To register a command that gets invoked when rows get updated in the switch table, enter:


.. code-block:: perl

  regnotif /usr/bin/mycmd switch  -o u



*****
FILES
*****


/opt/xcat/bin/regnotif


********
SEE ALSO
********


unregnotif(1)|unregnotif.1

