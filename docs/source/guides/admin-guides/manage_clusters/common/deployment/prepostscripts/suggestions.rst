Suggestions
------------

For writing scripts
~~~~~~~~~~~~~~~~~~~

   * Some compute node profiles exclude perl to keep the image as small as possible. If this is your case, your postscripts should obviously be written in another shell language, e.g. **bash,ksh**.
   * If a postscript is specific for an os, name your postscript mypostscript.osname.
   * Add logger statements to send errors back to the Management Node. By default, xCAT configures the syslog service on compute nodes to forward all syslog messages to the Management Node. This will help debug.

Using Hierarchical Clusters
~~~~~~~~~~~~~~~~~~~~~~~~~~~

If you are running a hierarchical cluster, one with Service Nodes. If your /install/postscripts directory is not mounted on the Service Node. You are going to need to sync or copy the postscripts that you added or changed in the **/install/postscripts** on the MN to the SN, before running them on the compute nodes. To do this easily, use the ``xdcp`` command and just copy the entire **/install/postscripts** directory to the servicenodes ( usually in /xcatpost ). ::

  xdcp service -R /install/postscripts/* /xcatpost
  or
  prsync /install/postscripts service:/xcatpost

If your **/install/postscripts** is not mounted on the Service Node, you should also: ::

  xdcp service -R /install/postscripts/* /install
  or
  prsync /install/postscripts service:/install
