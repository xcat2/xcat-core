Validating Kits
---------------

After modifying the ``buildkit.conf`` file and copying all the necessary files to the kit directories, use the ``chkconfig`` option on :doc:`buildkit </guides/admin-guides/references/man1/buildkit.1>` to validate the configuration file:  ::

    buildkit chkconfig

This command will verify all required fields defined in the buildkit.conf.  If errors are found, fix the specified error and rerun the command until all fields are validated. 

