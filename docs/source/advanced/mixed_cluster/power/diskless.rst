Provision x86 Diskless
======================

Troubleshooting
---------------

**Error:** The following Error message comes out when running nodeset: ::

    Error: Unable to find pxelinux.0 at /opt/xcat/share/xcat/netboot/syslinux/pxelinux.0

**Resolution:** 

The syslinux network booting files are missing.  
Install the sylinux-xcat package provided in the xcat-deps repository: ``yum -y install syslinux-xcat``

