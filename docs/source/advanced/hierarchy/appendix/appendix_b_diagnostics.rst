Appendix B: Diagnostics
=======================

* **root ssh keys not setup** -- If you are prompted for a password when ssh to
  the service node, then check to see if /root/.ssh has authorized_keys. If
  the directory does not exist or no keys, on the MN, run xdsh service -K,
  to exchange the ssh keys for root. You will be prompted for the root
  password, which should be the password you set for the key=system in the
  passwd table.
* **XCAT rpms not on SN** --On the SN, run rpm -qa | grep xCAT and make sure
  the appropriate xCAT rpms are installed on the servicenode. See the list of
  xCAT rpms in :ref:`setup_service_node_stateful_label`. If rpms
  missing check your install setup as outlined in Build the Service Node
  Stateless Image for diskless or :ref:`setup_service_node_stateful_label` for
  diskful installs.
* **otherpkgs(including xCAT rpms) installation failed on the SN** --The OS
  repository is not created on the SN. When the "yum" command is processing
  the dependency, the rpm packages (including expect, nmap, and httpd, etc)
  required by xCATsn can't be found. In this case, please check whether the
  ``/install/postscripts/repos/<osver>/<arch>/`` directory exists on the MN.
  If it is not on the MN, you need to re-run the "copycds" command, and there
  will be some file created under the
  ``/install/postscripts/repos/<osver>/<arch>`` directory on the MN. Then, you
  need to re-install the SN, and this issue should be gone.
* **Error finding the database/starting xcatd** -- If on the Service node when
  you run tabdump site, you get "Connection failure: IO::Socket::SSL:
  connect: Connection refused at ``/opt/xcat/lib/perl/xCAT/Client.pm``". Then
  restart the xcatd daemon and see if it passes by running the command:
  service xcatd restart. If it fails with the same error, then check to see
  if ``/etc/xcat/cfgloc`` file exists. It should exist and be the same as
  ``/etc/xcat/cfgloc`` on the MN. If it is not there, copy it from the MN to
  the SN. The run service xcatd restart. This indicates the servicenode
  postscripts did not complete successfully. Check to see your postscripts
  table was setup correctly in :ref:`add_service_node_postscripts_label` to the
  postscripts table.
* **Error accessing database/starting xcatd credential failure**-- If you run
  tabdump site on the servicenode and you get "Connection failure:
  IO::Socket::SSL: SSL connect attempt failed because of handshake
  problemserror:14094418:SSL routines:SSL3_READ_BYTES:tlsv1 alert unknown ca
  at ``/opt/xcat/lib/perl/xCAT/Client.pm``", check ``/etc/xcat/cert``. The
  directory should contain the files ca.pem and server-cred.pem. These were
  suppose to transfer from the MN ``/etc/xcat/cert`` directory during the
  install. Also check the ``/etc/xcat/ca`` directory. This directory should
  contain most files from the ``/etc/xcat/ca`` directory on the MN. You can
  manually copy them from the MN to the SN, recursively. This indicates the
  the servicenode postscripts did not complete successfully. Check to see
  your postscripts table was setup correctly in
  :ref:`add_service_node_postscripts_label` to the postscripts table. Again
  service xcatd restart and try the tabdump site again.
* **Missing ssh hostkeys** -- Check to see if ``/etc/xcat/hostkeys`` on the SN,
  has the same files as ``/etc/xcat/hostkeys`` on the MN. These are the ssh
  keys that will be installed on the compute nodes, so root can ssh between
  compute nodes without password prompting. If they are not there copy them
  from the MN to the SN. Again, these should have been setup by the
  servicenode postscripts.

* **Errors running hierarchical commands such as xdsh** -- xCAT has a number of
  commands that run hierarchically. That is, the commands are sent from xcatd
  on the management node to the correct service node xcatd, which in turn
  processes the command and sends the results back to xcatd on the management
  node. If a hierarchical command such as xcatd fails with something like
  "Error: Permission denied for request", check ``/var/log/messages`` on the
  management node for errors. One error might be "Request matched no policy
  rule". This may mean you will need to add policy table entries for your
  xCAT management node and service node:

