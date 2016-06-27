Log Collecting: Collecting logs of the whole installation process
-----------------------------------------------------------------

The ability to collect logs during the installation(diskfull and diskless) can be enabled by setting the "site.xcatdebugmode" to different levels(0,1,2), which is quite helpful when debugging installation problems.

The logs during diskfull provision:
```````````````````````````````````

* Pre-Install logs: the logs of pre-installation scripts, the pre-installation scripts include "%pre" section in anaconda, "<pre-scripts/>" section for SUSE and "partman/early_command" and "preseed/early_command" sections for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

* Installer logs: the logs from the os installer itself, i.e, the logs of installation program(anaconda, autoyast and preseed,etc.)

* Post-Install logs: the logs of post-installation scripts, the post-installation scripts include "%post" section in anaconda, "<chroot-scripts/>" and "<post-scripts/>" sections for SUSE and "preseed/late_command" section for ubuntu. The logs include the STDOUT and STDERR of the scripts as well as the debug trace output of bash scripts with "set -x"

* PostBootScript logs: the logs during the post boot scripts execution, which are specified in "postbootscripts" attribute of node and osimage definition and run during the 1st reboot after installation.

+---------------------+--------------+--------------+--------------+
|  **xcatdebugmode**  |       0      |       1      |       2      |
+---------------------+----+----+----+----+----+----+----+----+----+
| OS Distribution     |RHEL|SLES|UBT |RHEL|SLES|UBT |RHEL|SLES|UBT |
+================+====+====+====+====+====+====+====+====+====+====+
| Pre-Install    | MN | N            | N            | N            |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | C1           | C1   C2      | C1   C2      |
+----------------+----+----+----+----+----+----+----+----+----+----+
| Installer      | MN | N  | N  | N  | M1 | M1 | M1 | M1 | M1 | M1 |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 | C3 |
+----------------+----+----+----+----+----+----+----+----+----+----+
| Post-Install   | MN | M2           | M3           | M3           |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | C1           | C1   C2      | C1   C2      |
+----------------+----+----+----+----+----+----+----+----+----+----+
| PostBootScript | MN | M2           | M3           | M3           |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | C1           | C1   C2      | C1   C2      |
+----------------+----+----+----+----+----+----+----+----+----+----+

The logs during diskless provision:
```````````````````````````````````

* Provision logs: the logs during the diskless provision.

* PostBootScript logs: the logs during the post boot scripts execution, which are specified in "postbootscripts" attribute of node and osimage definition and run during the 1st reboot after installation.

+---------------------+--------------+--------------+--------------+
|  **xcatdebugmode**  |      0       |       1      |       2      |
+---------------------+----+----+----+----+----+----+----+----+----+
| OS Distribution     |RHEL|SLES|UBT |RHEL|SLES|UBT |RHEL|SLES|UBT |
+================+====+====+====+====+====+====+====+====+====+====+
| Provision      | MN | N            | M3           | M3           |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | N            | N            | N            |
+----------------+----+----+----+----+----+----+----+----+----+----+
| PostBootScript | MN | M3           | M3   M4      | M3   M4      |
+  logs          +----+----+----+----+----+----+----+----+----+----+
|                | CN | C1           | C1   C2      | C1   C2      |
+----------------+----+----+----+----+----+----+----+----+----+----+

MN: the logs forwarded to management node(M1-M4 is the operation for MN). ::

    M1 means the installer logs can be forwarded to the MN in ``/var/log/xcat/computes.log`` file.

    M2 means the error messages can be forwarded to ``/var/log/xcat/computes.log`` file on MN only when critical error happens.

    M3 means the installation logs can be forwarded to ``/var/log/xcat/computes.log`` file on MN.

    M4 means the debug trace("set -x" or "-o xtrace") of bash scripts enabled.

    N means the logs can not be forwarded to MN.

CN: the logs on compute node(C1-C3 is the operation for CN). ::

    C1 means the installation logs can be saved to ``/var/log/xcat/xcat.log`` file on CN.

    C2 means the debug trace("set -x" or "-o xtrace") of bash scripts enabled.

    C3 means the installer logs can be saved to the CN in ``/var/log/anaconda`` for RHEL, ``/var/log/YaST2`` for SLES, ``/var/log/installer`` for UBT.

    N means the logs can not be saved to CN.

