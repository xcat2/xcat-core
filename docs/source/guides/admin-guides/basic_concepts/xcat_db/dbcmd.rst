Database Commands
=================

There are 5 database related commands in xCAT:

* ``tabdump`` : Displays the header and all the rows of the specified table in CSV (comma separated values) format.

* ``tabedit`` : Opens the specified table in the user's editor, allows them to edit any text, and then writes changes back to the database table.  The table is flattened into a CSV (comma separated values) format file before giving it to the editor.  After the editor is exited, the CSV file will be translated back into the database format. 

* ``tabgrep`` : List table names in which an entry for the given node appears.

* ``dumpxCATdb`` : Dumps all the xCAT db tables to CSV files under the specified directory, often used to backup the xCAT database in xCAT reinstallation or management node migration.  

* ``restorexCATdb`` : Restore the xCAT db tables with the CSV files under the specified directory.


For the complete reference on all the xCAT database related commands, please refer to the xCAT manpage with ``man <command>``
