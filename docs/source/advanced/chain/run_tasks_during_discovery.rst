Run Task List During Discovery
==============================

To run a list of tasks during the discovery, set the tasks in the chain table by using the ``chdef`` command to change the chain attribute, before powering on the nodes. For example: ::

    chdef <noderange> chain='runcmd=bmcsetup,osimage=<osimage name>'

These tasks will be run after the discovery.

