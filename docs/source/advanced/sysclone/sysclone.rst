Using System Clone to Deploy Diskful Node
=========================================

When we want to deploy large numbers of nodes which have the same configuration, the simplest way is to clone. This means the user can customize and tweak one node's configuration according to his needs. They can verify it's proper operation, then make this node as template. They can capture an osimage from this template node, and deploy the rest of the nodes with this osimage quickly. xCat (2.8.2 and above) provides this feature which we call Sysclone to help you handle this scenario. 

List of Supported Arch and OS
-----------------------------

+------------------+-------------+----------------+-------------+------------------------------------------------------+
|   xCAT version   |     OS      | Tested Version | ARCH        |                Feature                               |
+==================+=============+================+=============+======================================================+
| 2.8.2 and later  | CentOS      | 6.3 5.9        | x86_64      | Basic clone node                                     |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | RHEL        | 6.4 5.9        | x86_64      | Basic clone node                                     |
+------------------+-------------+----------------+-------------+------------------------------------------------------+
| 2.8.3 and later  | SLES        | 11.3 10.4      | x86_64      | Basic clone node                                     |
+------------------+-------------+----------------+-------------+------------------------------------------------------+
| 2.8.5 and later  | CentOS      | 6.3            | x86_64      | Add feature: update delta changes(has limitation)    |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | RHEL        | 6.4            | x86_64      | Add feature: update delta changes(has limitation)    |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | SLES        | 11.3           | x86_64      | Add feature: update delta changes                    |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | SLES        | 10.x           | x86_64      | Not support any more                                 |
+------------------+-------------+----------------+-------------+------------------------------------------------------+
| 2.9 and later    | RHEL        | 6.4            | ppc64       | Basic clone node/update delta changes/LVM            |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | SLES        | 11.3           | ppc64       | Basic clone node/update delta changes                |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | RHEL        | 7.0            | ppc64       | Basic clone node/update delta changes/LVM            |
+                  +-------------+----------------+-------------+------------------------------------------------------+
|                  | RHEL        | 6.4 7.0        | x86_64      | support LVM                                          |
+------------------+-------------+----------------+-------------+------------------------------------------------------+

Using Sysclone to Install Nodes
-------------------------------

This document describes how to install and configure a template node (called golden client), capture an image from this template node. Then using this image to deploy other same nodes (called target nodes) quickly. 

Prepare the xCAT Management Node for Support Sysclone
`````````````````````````````````````````````````````

To configure xCAT management node refer to section :ref:`install_guides`

For support Sysclone, we need to install some extra rpms on management node and the golden client.

1. Download the xcat-dep tarball (xcat-dep-XXX.tar.bz2) which includes extra rpms needed by Sysclone. (You might already have the xcat-dep tarball on management node. If not, go to `xcat-dep  <http://xcat.org/files/xcat-dep/2.x_Linux>`_ and get the latest xCAT dependency tarball.)

2. Install systemimager server on management node

* **[RH/CentOS]**::

     yum -y install systemimager-server

* **[SLES]**::

     zypper -n install systemimager-server

*[Note] Maybe you will encounter below failed message when you install systemimager-server, just ignore it.*::

    Can't locate AppConfig.pm in @INC (@INC contains: /usr/lib/systemimager/perl /usr/local/lib64/perl5 /usr/local/share/perl5 /usr/lib64/perl5/vendor_perl /usr/share/perl5/vendor_perl /usr/lib64/perl5 /usr/share/perl5 .) at /usr/lib/systemimager/perl/SystemImager/Config.pm line 13.
    BEGIN failed--compilation aborted at /usr/lib/systemimager/perl/SystemImager/Config.pm line 13.
    Compilation failed in require at /usr/lib/systemimager/perl/SystemImager/Server.pm line 17.
    BEGIN failed--compilation aborted at /usr/lib/systemimager/perl/SystemImager/Server.pm line 17.
    Compilation failed in require at /usr/sbin/si_mkrsyncd_conf line 28.
    BEGIN failed--compilation aborted at /usr/sbin/si_mkrsyncd_conf line 28.

3. Do some preparation for install and configure golden client in management node. Copy the xcat-dep-XXX.tar.bz2 file to directory ``/install/post/otherpkgs/<os>/<arch>/xcat/`` of the management node according your golden client's OS version and system architecture, then decompression it. For example: 

* **[CentOS6.3 and x86_64]**::
    
    mkdir -p /install/post/otherpkgs/CentOS6.3/x86_64/xcat
    cp xcat-dep-*.tar.bz2  /install/post/otherpkgs/CentOS6.3/x86_64/xcat
    cd /install/post/otherpkgs/CentOS6.3/x86_64/xcat
    tar jxvf xcat-dep-*.tar.bz2

* **[SLES11.3 and x86_64]**::

    mkdir -p /install/post/otherpkgs/SLES11.3/x86_64/xcat
    cp xcat-dep-*.tar.bz2  /install/post/otherpkgs/SLES11.3/x86_64/xcat
    cd /install/post/otherpkgs/SLES11.3/x86_64/xcat
    tar jxvf xcat-dep-*.tar.bz2

* **[RHEL6.4 and ppc64]**::
    
    mkdir -p /install/post/otherpkgs/rhels6.4/ppc64/xcat
    cp xcat-dep-*.tar.bz2  /install/post/otherpkgs/rhels6.4/ppc64/xcat
    cd /install/post/otherpkgs/rhels6.4/ppc64/xcat
    tar jxvf xcat-dep-*.tar.bz2

Install and Configure the Golden Client	
```````````````````````````````````````
	
The Golden Client acts as a regular node for xCAT, just have some extra rpms to support clone. When you deploy golden client with xCAT, you just need to add a few additional definitions to the image which will be used to deploy golden client.

For information of how to install a regular node, refer to section :ref:`Diskful Installation <diskful_installation>`

For support clone, add 'otherpkglist' and 'otherpkgdir' attributes to the image definition which will be used to deploy golden client, then deploy golden client as normal. then the golden client will have extra rpms to support clone. If you have deployed your golden client already, using 'updatenode' command to push these extra rpms to golden client. CentOS share the same pkglist file with RHEL. For example: 

* **[RH6.4 and x86_64]**::

    chdef -t osimage -o <osimage-name> otherpkglist=/opt/xcat/share/xcat/instal/rh/sysclone.rhels6.x86_64.otherpkgs.pkglist
    chdef -t osimage -o <osimage-name> -p otherpkgdir=/install/post/otherpkgs/rhels6.4/x86_64
    updatenode <golden-cilent> -S

* **[CentOS6.3 and x86_64]**::

    chdef -t osimage -o <osimage-name> otherpkglist=/opt/xcat/share/xcat/install/rh/sysclone.rhels6.x86_64.otherpkgs.pkglist
    chdef -t osimage -o <osimage-name> -p otherpkgdir=/install/post/otherpkgs/CentOS6.3/x86_64
    updatenode <golden-cilent> -S

* **[SLES11.3 and x86_64]**::
 
    chdef -t osimage -o <osimage-name> otherpkglist=/opt/xcat/share/xcat/install/sles/sysclone.sles11.x86_64.otherpkgs.pkglist
    chdef -t osimage -o <osimage-name> -p otherpkgdir=/install/post/otherpkgs/SLES11.3/x86_64
    updatenode <golden-cilent> -S

* **[RH6.3 and ppc64]**::

    chdef -t osimage -o <osimage-name> otherpkglist=/opt/xcat/share/xcat/install/rh/sysclone.rhels6.ppc64.otherpkgs.pkglist
    chdef -t osimage -o <osimage-name> -p otherpkgdir=/install/post/otherpkgs/rhels6.3/ppc64
    updatenode <golden-cilent> -S

*[Note]: If you install systemimager RPMs on CentOS 6.5 node by above steps, you maybe hit failure. this is a known issue because some defect of CentOS6.5 itself. Refer to known issue section for help.*

Capture Image from Golden Client
````````````````````````````````

On Management node, use xCAT command 'imgcapture' to capture an image from the golden-client.:: 

    imgcapture <golden-client> -t sysclone -o <mycomputeimage>

When imgcapture is running, it pulls the image from the golden-client, and creates a image files system and a corresponding osimage definition on the xcat management node. You can use below command to check the osimage attributes.::

    lsdef -t osimage <mycomputeimage>

Install the target nodes with the image from the golden-client
``````````````````````````````````````````````````````````````

following below commands to install the target nodes with the image captured from golden client.

* **[x86_64]**::

    nodeset <target-node> osimage=<mycomputeimage>
    rsetboot <target-node> net
    rpower <target-node> boot

* **[ppc64]**::

    nodeset <target-node> osimage=<mycomputeimage>
    rnetboot <target-node>

.. _update-node-later-on:

Update Nodes Later On
---------------------

If, at a later time, you need to make changes to the golden client (install new rpms, change config files, etc.), you can capture the changes and push them to the already cloned nodes without need to restart cloned nodes. This process will only transfer the deltas, so it will be much faster than the original cloning.

**[Limitation]**: In xcat2.8.5, this feature has limitation in RHEL and CentOS. when your delta changes related bootloader, it would encounter error. This issue will be fixed in xcat higher version. So up to now, in RHEL and CentOS, this feature just update files not related bootloader.

Update delta changes follow below steps:

1. Make changes to your golden node (install new rpms, change config files, etc.).

2. From the mgmt node, capture the image using the same command as before. Assuming <myimagename> is an existing image, this will only sync the changes to the image on the Management node::

     imgcapture <golden-client> -t sysclone -o <myimagename>

3. To synchronize the changes to your target nodes do the following:

a) If you are running xCAT 2.8.4 or older:

From one of the nodes you want to update, test the update to see which files will be updated::

    xdsh <target-node> -s 'si_updateclient --server <mgmtnode-ip> --dry-run --yes'

	
If it lists files and directories that you do not think should be updated, you need to add them to the exclude list in 3 places

* On the golden node: ``/etc/systemimager/updateclient.local.exclude``
* On the mgmt node: ``/install/sysclone/images/<myimagename>/etc/systemimager/updateclient.local.exclude``
* On all of the nodes to be updated: ``/etc/systemimager/updateclient.local.exclude``

From the mgmt node, push the updates out to the other nodes::

    xdsh <target-node-range> -s 'si_updateclient --server <mgmtnode-ip> --yes'

b) If you are running xCAT 2.8.5 or later:

You could push the updates out to the other nodes quickly by below command::

    updatenode <target-node-range> -S

	
Known Issue
-----------

Can not install systemimager RPMs in CentOS6.5 by yum
``````````````````````````````````````````````````````

If you install systemimager RPMs on CentOS 6.5 node using yum, you may experience some problems due to CentOS6.5 itself. If that happens, copy related RPMs to CentOS 6.5 node and install them by hand.

* **On management node**::

    [root@MN]# cd /<path-to-xcat-dep>/xcat-dep
    [root@MN xcat-dep]# scp systemimager-client-4.3.0-0.1.noarch.rpm \
                            systemconfigurator-2.2.11-1.noarch.rpm \
                            systemimager-common-4.3.0-0.1.noarch.rpm \
                            perl-AppConfig-1.52-4.noarch.rpm   <CentOS-node-ip>:/<savepath>

* **On golden client**::

    [root@CentOS6.5 node]# cd /<savepath>
    [root@CentOS6.5 node]# rpm -ivh perl-AppConfig-1.52-4.noarch.rpm 
    [root@CentOS6.5 node]# rpm -ivh systemconfigurator-2.2.11-1.noarch.rpm
    [root@CentOS6.5 node]# rpm -ivh systemimager-common-4.3.0-0.1.noarch.rpm
    [root@CentOS6.5 node]# rpm -ivh systemimager-client-4.3.0-0.1.noarch.rpm

Kernel panic at times when install target node with rhels7.0 in Power 7 server
``````````````````````````````````````````````````````````````````````````````

When you clone rhels7.0 image to target node which is Power 7 server lpar, maybe you will hit Kernel panic problem at times after boot loader grub2 download kernel and initrd. This is an known issue but without resolve yet. up to now, we recommend you try again. 
