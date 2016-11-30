2016-11-30 - Removal of Service Stream Password
===============================================

It has been brought to our attention that the xCAT product has hard-coded default passwords for the HMC/FSP to allow for IBM Service to connect to customer machines for L2/L3 support activities.  This creates a security vulnerability where third parties could potentially gain root level access using these weak, hard coded passwords.


    Example: ::

        create_pwd => "netsDynPwdTool --create dev FipSdev",
        password => "FipSdev"


In response, xCAT will remove these hard-coded password and interfaces from the xCAT code.


Action
------

No action is required for xCAT 2.12.3, and higher.

If running older versions of xCAT, update xCAT to a higher level code base that has the hard-coded default passwords removed.

The following table describes the recommended update path: 

+-------------------------+-----------------------------------------------+---------------------------------------+
| xCAT Version            | Action                                        | Release Notes                         |
+=========================+===============================================+=======================================+
| **2.13**, or newer      | No applicable                                 |                                       |
|                         |                                               |                                       |
+-------------------------+-----------------------------------------------+---------------------------------------+
| **2.12.x**              | Update to **2.12.3**, or higher               | `2.12.3 Release Notes <https://       |
|                         |                                               | github.com/xcat2/xcat-core/wiki       |
|                         |                                               | /XCAT_2.12.3_Release_Notes>`_         |
+-------------------------+-----------------------------------------------+---------------------------------------+
| **2.11.x**              | Update to **2.12.3**, or higher               | `2.12.3 Release Notes <https://       |
|                         |                                               | github.com/xcat2/xcat-core/wiki       |
|                         |                                               | /XCAT_2.12.3_Release_Notes>`_         |
+-------------------------+-----------------------------------------------+---------------------------------------+
| **2.10.x**              | Update to **2.12.3**, or higher               | `2.12.3 Release Notes <https://       |
|                         |                                               | github.com/xcat2/xcat-core/wiki       |
|                         |                                               | /XCAT_2.12.3_Release_Notes>`_         |
+-------------------------+-----------------------------------------------+---------------------------------------+
| **2.9.x**, or older     | Update to:                                    | `2.9.4 Release Notes <https://        |
|                         |                                               | github.com/xcat2/xcat-core/wiki       |
|                         | - **2.9.4**, or higher for **AIX**            | /XCAT_2.9.4_Release_Notes>`_          |
|                         | - **2.12.3**, or higher for **LINUX**         |                                       |
+-------------------------+-----------------------------------------------+---------------------------------------+

