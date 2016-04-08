Log Collecting: Collecting logs of the whole installation process
-----------------------------------------------------------------

The ability to collect logs during the installation process can be helpful when debugging installation problems.

Pre-Install: the logs of pre-installation scripts, the pre-installation scripts include "%pre" section in anaconda, "<pre-scripts/>" section for SUSE and "partman/early_command" and "preseed/early_command" sections for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

Installer: the logs from the os installer itself, i.e, the logs of installation program(anaconda, autoyast and preseed,etc.)

Post-Install: the logs of post-installation scripts, the post-installation scripts include "%post" section in anaconda, "<chroot-scripts/>" and "<post-scripts/>" sections for SUSE and "preseed/late_command" section for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

Post-Script: This section is useful for functions such as updating node status. This section contains the postbootscripts.

The following behavior is observed during OS install:

+------------------+--------------+--------------+--------------+
|**xcatdebugmode** |      0       |       1      |       2      |
+------------------+----+----+----+----+----+----+----+----+----+
|                  |RHEL|SLES|UBT |RHEL|SLES|UBT |RHEL|SLES|UBT |
+=============+====+====+====+====+====+====+====+====+====+====+
| Pre-Install | MN | N            | N            | N            |
+  log        +----+----+----+----+----+----+----+----+----+----+
|             | CN | Y1           | Y2           | Y2           |
+-------------+----+----+----+----+----+----+----+----+----+----+
| Installer   | MN | N  | N  | N  | Y6 | Y6 | N  | Y6 | Y6 | N  |
+  log        +----+----+----+----+----+----+----+----+----+----+
|             | CN | Y5 | Y5 | Y5 | Y5 | Y5 | Y5 | Y5 | Y5 | Y5 |
+-------------+----+----+----+----+----+----+----+----+----+----+
| Post-Install| MN | Y4           | Y3           | Y3           |
+  log        +----+----+----+----+----+----+----+----+----+----+
|             | CN | Y1           | Y2           | Y2           |
+-------------+----+----+----+----+----+----+----+----+----+----+
| Post-Script | MN | Y4           | Y3           | Y3           |
+  log        +----+----+----+----+----+----+----+----+----+----+
|             | CN | Y1           | Y2           | Y2           |
+-------------+----+----+----+----+----+----+----+----+----+----+

Y1 means the installation logs can be saved to ``/var/log/xcat/xcat.log`` file on CN.

Y2 means the installation logs and debug trace("set -x" or "-o xtrace") of bash scripts can be saved to ``/var/log/xcat/xcat.log`` file on CN.

Y3 means the installation logs can be forwarded to ``/var/log/xcat/computes.log`` file on MN.

Y4 means the error messages can be forwarded to ``/var/log/xcat/computes.log`` file on MN only when critical error happens.

Y5 means the installer log can be saved to the CN in ``/var/log/anaconda`` for RHEL, ``/var/log/YaST2`` for SLES, ``/var/log/installer`` for UBT.

Y6 means the installer log can be forwarded to the MN in ``/var/log/xcat/computes.log`` file.

N means the logs can not be forwarded or saved.

