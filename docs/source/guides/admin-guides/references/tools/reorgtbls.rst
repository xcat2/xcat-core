reorgtbls
=========

::

    DB2 Table Reorganization utility.
    This script can be set as a cron job or run on the command line to reorg the xcatdb DB2 database tables. It automatically added as a cron job, if you use the db2sqlsetup command to create your DB2 database setup for xCAT. 
    Usage:
            --V - Verbose mode
            --h - usage
            --t -comma delimited list of tables.
                 Without this flag it reorgs all tables in the xcatdb database .
    
Author:  Lissa Valletta
