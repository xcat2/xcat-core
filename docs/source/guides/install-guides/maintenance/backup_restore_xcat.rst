Backup and Restore xCAT
=======================

It's useful to backup xcat data sometime. For example, you need to upgrading to another version of xCAT, or you need to change management server and move xcat form one to another, or you need to make backups regularly and restore production environment for any accident. Below section will help you backup and restore xcat data.

Backup User Data
----------------

If need to backup xcat database, you can use :doc:`dumpxCATdb </guides/admin-guides/references/man1/dumpxCATdb.1>` command like below.  ::

    dumpxCATdb -p <path_to_save_the_database>

**[Note]** Maybe you need to dump some environment data for problem report when you hit defect, you can use :doc:`xcatsnap </guides/admin-guides/references/man8/xcatsnap.8>` command like below. ::

    xcatsnap -B -d <path_to_save_the_data> 


Restore User Data
-----------------

If need to restore xCAT environment, after :doc:`xCAT software installation </guides/install-guides/index>`, you can restore xCAT DB using the :doc:`restorexCATdb </guides/admin-guides/references/man1/restorexCATdb.1>` command pointing to the data files dumped in the past.    ::

    restorexCATdb -p  <path_to_save_the_database>


