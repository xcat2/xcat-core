Log Collecting: Collecting logs of the whole installation process
-----------------------------------------------------------------

The ability to collect logs during the installation(diskfull and diskless) can be enabled by setting the "site.xcatdebugmode" to different levels(0,1,2), which is quite helpful when debugging installation problems.

The logs during diskfull provision:
```````````````````````````````````

* Pre-Install logs: the logs of pre-installation scripts, the pre-installation scripts include "%pre" section in anaconda, "<pre-scripts/>" section for SUSE and "partman/early_command" and "preseed/early_command" sections for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

* Installer logs: the logs from the os installer itself, i.e, the logs of installation program(anaconda, autoyast and preseed,etc.)

* Post-Install logs: the logs of post-installation scripts, the post-installation scripts include "%post" section in anaconda, "<chroot-scripts/>" and "<post-scripts/>" sections for SUSE and "preseed/late_command" section for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

* PostBootScript logs: the logs during the post boot scripts execution, which are specified in "postbootscripts" attribute of node and osimage definition and run during the 1st reboot after installation.

+------------------------+-----------------------+-----------------------+-----------------------+
|  **xcatdebugmode**     |       0               |       1               |       2               |
+------------------------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| OS Distribution        | RHEL  | SLES  | UBT   | RHEL  | SLES  | UBT   | RHEL  | SLES  | UBT   |
+================+=======+=======+=======+=======+=======+=======+=======+=======+=======+=======+
| Pre-Install    | [MN]_ | [N]_                  | [N]_                  | [N]_                  |
+  logs          +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
|                | [CN]_ | [Y1]_                 | [Y2]_                 | [Y2]_                 |
+----------------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| Installer      | [MN]_ | [N]_  | [N]_  | [N]_  | [Y7]_ | [Y7]_ | [Y7]_ | [Y7]_ | [Y7]_ | [Y7]_ |
+  logs          +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
|                | [CN]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ | [Y6]_ |
+----------------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| Post-Install   | [MN]_ | [Y5]_                 | [Y3]_                 | [Y3]_                 |
+  logs          +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
|                | [CN]_ | [Y1]_                 | [Y2]_                 | [Y2]_                 |
+----------------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
| PostBootScript | [MN]_ | [Y5]_                 | [Y3]_                 | [Y3]_                 |
+  logs          +-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+
|                | [CN]_ | [Y1]_                 | [Y2]_                 | [Y2]_                 |
+----------------+-------+-------+-------+-------+-------+-------+-------+-------+-------+-------+

The logs during diskless provision:
```````````````````````````````````

* Provision logs: the logs during the diskless provision.

* PostBootScript logs: the logs during the post boot scripts execution, which are specified in "postbootscripts" attribute of node and osimage definition and run during the 1st reboot after installation.

+------------------------+--------------+--------------+--------------+
|  **xcatdebugmode**     |      0       |       1      |       2      |
+------------------------+----+----+----+----+----+----+----+----+----+
| OS Distribution        |RHEL|SLES|UBT |RHEL|SLES|UBT |RHEL|SLES|UBT |
+================+=======+====+====+====+====+====+====+====+====+====+
| Provision      | [MN]_ | [N]_         | [Y3]_        | [Y3]_        |
+  logs          +-------+----+----+----+----+----+----+----+----+----+
|                | [CN]_ | [N]_         | [N]_         | [N]_         |
+----------------+-------+----+----+----+----+----+----+----+----+----+
| PostBootScript | [MN]_ | [Y3]_        | [Y4]_        | [Y4]_        |
+  logs          +-------+----+----+----+----+----+----+----+----+----+
|                | [CN]_ | [Y1]_        | [Y2]_        | [Y2]_        |
+----------------+-------+----+----+----+----+----+----+----+----+----+

.. [MN] means the logs forwarded to management node.

.. [CN] means the logs on compute node.

.. [Y1] means the installation logs can be saved to ``/var/log/xcat/xcat.log`` file on CN.

.. [Y2] means the installation logs and debug trace("set -x" or "-o xtrace") of bash scripts can be saved to ``/var/log/xcat/xcat.log`` file on CN.

.. [Y3] means the installation logs can be forwarded to ``/var/log/xcat/computes.log`` file on MN.

.. [Y4] means the installation logs and debug trace("set -x" or "-o xtrace") of bash scripts can be forwarded to ``/var/log/xcat/computes.log`` file on MN.

.. [Y5] means the error messages can be forwarded to ``/var/log/xcat/computes.log`` file on MN only when critical error happens.

.. [Y6] means the installer log can be saved to the CN in ``/var/log/anaconda`` for RHEL, ``/var/log/YaST2`` for SLES, ``/var/log/installer`` for UBT.

.. [Y7] means the installer log can be forwarded to the MN in ``/var/log/xcat/computes.log`` file.

.. [N] means the logs can not be forwarded or saved.

