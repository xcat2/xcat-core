Using Updatenode
================

Introduction
------------------

After initial node deployment, you may need to make changes/updates to your nodes. The ``updatenode`` command is for this purpose. It allows you to add or modify the followings on your nodes:

#. Add additional software
#. Re-run postscripts or run additional postscripts
#. Synchronize new/updated configuration files
#. Update ssh keys and xCAT certificates

Each of these will be explained in the document. The basic way to use ``updatenode`` is to set the definition of nodes on the management node the way you want it and then run ``updatenode`` to push those changes out to the actual nodes. Using options to the command, you can control which of the above categories ``updatenode`` pushes out to the nodes.

Most of what is described in this document applies to **stateful** and **stateless** nodes.
In addition to the information in this document, check out the ``updatenode`` man page.

Add Additional Software
-------------------------

The packages that will be installed on the node are stored in the packages list files. There are **two kinds of package list files**:

#. The **package list file** contains the names of the packages that come from the os distro. They are stored in **.pkglist** file.
#. The **other package list file** contains the names of the packages that do **NOT** come from the os distro. They are stored in **.otherpkgs.pkglist** file.

Installing Additional OS Distro Packages
````````````````````````````````````````

For packages from the OS distro, add the new package names (without the version number) in the .pkglist file. If you have newer updates to some of your operating system packages that you would like to apply to your OS image, you can place them in another directory, and add that directory to your osimage pkgdir attribute. How to add additional OS distro packages, go to :ref:`Install-Additional-OS-Packages-label`

Note:If the objective node is not installed by xCAT, make sure the correct osimage pkgdir attribute so that you could get the correct repository data.

Install Additional non-OS Packages
``````````````````````````````````

If you have additional packages (packages not in the distro) that you also want installed, make a directory to hold them, create a list of the packages you want installed, and add that information to the osimage definition. How to add Additional Other Packages, go to :ref:`Install-Additional-Other-Packages-label`

Update Nodes
````````````

Run the ``updatenode`` command to push the new software to the nodes: ::

    updatenode <noderange> -S

The -S flag updates the nodes with all the new or updated packages specified in both .pkglist and .otherpkgs.pkglist.

If you have a configuration script that is necessary to configure the new software, then instead run: ::

    cp myconfigscript /install/postscripts/
    chdef -p -t compute postbootscripts=myconfigscript
    updatenode <noderange> ospkgs,otherpkgs,myconfigscript

The next time you re-install these nodes, the additional software will be automatically installed.

**If you update stateless nodes, you must also do this next step**, otherwise the next time you reboot the stateless nodes, the new software won't be on the nodes. Run genimage and packimage to install the extra rpms into the image: ::

    genimage <osimage>
    packimage <osimage>

Update the delta changes in Sysclone environment
````````````````````````````````````````````````
Updatenode can also be used in Sysclone environment to push delta changes to target node. After capturing the delta changes from the golden client to management node, just run below command to push delta changes to target nodes. See Sysclone environment related section: :ref:`update-node-later-on` for more information. ::

    updatenode <targetnoderange> -S

Rerun Postscripts or Run Additional Postcripts
--------------------------------------------------------------------------

You can use the ``updatenode`` command to perform the following functions after the nodes are up and running:

  * Rerun postscripts defined in the postscripts table.
  * Run any additional postscript one time.

Go to :ref:`Using Postscript <Using-Postscript-label>` to see how to configure postscript.

Go to :ref:`Using-Prescript-label` to see how to configure prepostscript.

To rerun all the postscripts for the nodes. (In general, xCAT postscripts are structured such that it is not harmful to run them multiple times.) ::

    updatenode <noderange> -P

To rerun just the syslog postscript for the nodes: ::

    updatenode <noderange> -P syslog

To run a list of your own postscripts, make sure the scripts are copied to /install/postscripts directory, then: ::

    updatenode <noderange> -P "script1,script2"

If you need to, you can also pass arguments to your scripts: ::

    updatenode <noderange> -P "script1 p1 p2,script2"

mypostscript template for ``updatenode``

You can customize what attributes you want made available to the postscript, using the shipped mypostscript.tmpl file :ref:`Using-the-mypostscript-template-label`.

Synchronize new/updated configuration files
-------------------------------------------

Setting up syncfile
```````````````````

Use instructions in doc: :ref:`The_synclist_file`.

Syncfiles to the nodes
```````````````````````

After compute node is installed, you would like to sync files to the nodes: ::

    updatenode <noderange> -F

With the ``updatenode`` command the syncfiles postscript cannot be used to sync files to the nodes.Therefore, if you run ``updatenode <noderange> -P syncfiles``, nothing will be done. A message will be logged that you must use ``updatenode <noderange> -F`` to sync files.

Update the ssh Keys and Credentials on the Nodes
------------------------------------------------

If after node deployment, the ssh keys or xCAT ssl credentials become corrupted, xCAT provides a way to quickly fix the keys and credentials on your service and compute nodes: ::

     updatenode <noderange> -K

Note: this option can't be used with any of the other updatenode options.

Appendix : Debugging Tips
--------------------------

Internally updatenode command uses the xdsh in the following ways:

Linux: xdsh <noderange> -e /install/postscripts/xcatdsklspost -m <server> <scripts&gt>

where <scripts> is a comma separated postscript like ospkgs,otherpkgs etc.

  * wget is used in xcatdsklspost/xcataixpost to get all the postscripts from the <server> to the node. You can check /tmp/wget.log file on the node to see if wget was successful or not. You need to make sure the  /xcatpost directory has enough space to hold the postscripts.
  * A file called /xcatpost/mypostscript (Linux) is created on the node which contains the environmental variables and scripts to be run. Make sure this file exists and it contains correct info. You can also run this file on the node manually to debug.
  * For ospkgs/otherpkgs, if /install is not mounted on the <server>, it will download all the rpms from the <server> to the node using wget. Make sure /tmp and /xcatpost have enough space to hold the rpms and check /tmp/wget.log for errors.
  * For ospkgs/otherpkgs, If zypper or yum is installed on the node, it will be used the command to install the rpms. Make sure to run createrepo on the source directory on the <server> every time a rpm is added or removed. Otherwise, the rpm command will be used, in this case, make sure all the necessary depended rpms are copied in the same source directory.
  * You can append -x on the first line of ospkgs/otherpkgs to get more debug info.

