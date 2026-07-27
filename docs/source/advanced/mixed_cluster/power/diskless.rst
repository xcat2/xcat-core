Provision x86 Diskless
======================

Troubleshooting
---------------

**Warning:** The following warning appears when ``nodeset`` generates a configuration that chains pxelinux: ::

    Warning: Unable to find pxelinux.0 from syslinux; nodes whose xNBA configuration chains pxelinux will not boot until it is available

**Resolution:**

The syslinux network booting files are missing.
Install the syslinux-xcat package provided in the xcat-deps repository: ``yum -y install syslinux-xcat``
