Enabling Debug Port: Running commands in the installer from MN
--------------------------------------------------------------

**This mode is supported with debug level set to 1 or 2**

xCAT creates a server in the **installer**, listening on port ``3001``. It executes commands sent to it from the xCAT MN and returns the response output.

The command ``runcmdinstaller`` can be used to send request to installer:

Usage: ``runcmdinstaller <node> "<command>"``

Note: Make sure all the commands are quoted by ``""``

To list all the items under the /etc directory in the installer: ``runcmdinstaller c910f03c01p03 "ls /etc"``
 
