Disable Python Framework
========================

By default, if ``xCAT-openbmc-py`` is installed and Python files are there, xCAT will default to running the Python framework.

A site table attribute is created to allow the ability to control between Python and Perl.

* To disable all Python code and revert to the Perl implementation:  ::

    chdef -t site clustersite openbmcperl=ALL

* To disable single commands, specify a command separated lists: ::

    chdef -t site clustersite openbmcperl="rpower,rbeacon"
