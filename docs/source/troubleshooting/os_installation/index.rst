Operating System Installation
=============================

The ability to access the installer or to collect logs during the installation process can be helpful when debugging installation problems.

A new attribute is provided in the **site** table called ``xcatdebugmode``.

* xcatdebugmode=0: Diagnostic entries will be shown in corresponding log files.
* xcatdebugmode=1: Diagnostic entries will be shown in corresponding log files and debug port will be opened.
* xcatdebugmode=2: Diagnostic entries will be shown in corresponding log files, debug port will be opened and SSH access is enabled.

Supported OS:

* RHEL: 6.7 and above
* SLES: 11.4 and above
* UBT: 14.04.3 and above

The following behavior is supported during OS installation:

+-----------------+--------------+--------------+--------------+
|**xcatdebugmode**|      0       |       1      |       2      |
+-----------------+----+----+----+----+----+----+----+----+----+
|                 |RHEL|SLES|UBT |RHEL|SLES|UBT |RHEL|SLES|UBT |
+=================+====+====+====+====+====+====+====+====+====+
| Log Collecting  | Y  | Y  | Y  | Y  | Y  | Y  | Y  | Y  | Y  |
+-----------------+----+----+----+----+----+----+----+----+----+
|Enable Debug Port| N  | N  | N  | Y  | Y  | Y  | Y  | Y  | Y  |
+-----------------+----+----+----+----+----+----+----+----+----+
|   SSH Access    | N  | N  | N  | N  | N  | N  | Y  | Y  | Y  |
+-----------------+----+----+----+----+----+----+----+----+----+

* Y - the behavior is supported by OS at specified **xcatdebugmode** level.

* N - the behavior is not supported.

Next chapter introduces the procedures on how to troubleshoot operating system installation.

.. toctree::
   :maxdepth: 2

   log_to_mn_cn.rst
   debug_port.rst
   ssh_enable.rst

