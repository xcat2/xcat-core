Operating System Installation
=============================

The ability to access the installer or to collect logs during the installation process can be helpful when debugging installation problems.

A new attribute is provided in the site table called ``xcatdebugmode``. ::

    xcatdebugmode=0: Only diagnose Log will be show in corresponding files.
    xcatdebugmode=1: Diagnose Log will be show in corresponding files and debug port will be opened.
    xcatdebugmode=2: SSH is supported while installing also with diagnose log show and debug port enable.

List of Supported OS. ::

    RHEL: 6.7 and above
    SLES: 11.4 and above
    UBT: 14.04.3 and above

The following behavior is observed during OS install:

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

Y means the behavior is supported by OS at current xcatdebugmode.

N means the opposite meaning.

This chapter introduces the procedures of how to troubleshoot operating system installation. Basically, it includes the following parts.

.. toctree::
   :maxdepth: 2

   log_to_mn_cn.rst
   debug_port.rst
   ssh_enable.rst

