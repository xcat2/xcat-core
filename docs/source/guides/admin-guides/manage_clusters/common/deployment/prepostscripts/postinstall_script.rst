.. _Using-Postinstallscript-label:

Using Postinstall Script
------------------------

xCAT will run scripts specified by postinstall attribute when executing **genimage** command. The scripts will be exectuted after the package installation but before initrd generation. One of the uses of postinstall script is to install drivers into the rootimage during the **genimage** run.

