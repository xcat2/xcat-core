Backup and Restore xCAT
=======================


Backup xCAT User Data
---------------------

Before removing xCAT, recommend to backup xCAT database. It's convenient to restore xCAT management environment in the future if needed. ::

    dumpxCATdb -p <path_to_save_the_database>

For more information of on ``dumpxCATdb``, please refer to :doc:`dumpxCATdb </guides/admin-guides/references/man1/dumpxCATdb.1>`. 




Restore xCAT User Data
----------------------

If need to restore xCAT environment, after :doc:`xCAT software installation </guides/install-guides/index>`, you can restore xCAT DB by data files dumped in the past. ::

    restorexCATdb -p  <path_to_save_the_database>

For more information of on ``restorexCATdb``, please refer to :doc:`restorexCATdb </guides/admin-guides/references/man1/restorexCATdb.1>`.

