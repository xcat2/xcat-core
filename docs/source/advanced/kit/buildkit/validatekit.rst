Validating the Kit Configuration
--------------------------------

After modify the buildkit.conf file and copy all necessary files to the kit directories, use the ``chkconfig`` subcommand to validate the build configuration file.  ::

  buildkit chkconfig

This command will verify all required fields defined in the buildkit.conf, included all internally referenced attributes and all referenced files.

Fix any errors then rerun this command until all the fields are validated.
