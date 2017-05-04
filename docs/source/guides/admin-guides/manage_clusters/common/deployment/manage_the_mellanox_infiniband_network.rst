Managing the Mellanox Infiniband Network
========================================

Mellanox IB Drives Installation
-------------------------------

The Sample Postscript of IB Drivers Installation
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

XCAT provides one sample postscript to help you install the **Mellanox OpenFabrics Enterprise Distribution** (OFED) Infiniband Driver. This shell script is ``/opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install``. You can use this script directly, or just refer to it than change it to satisfy your own environment. From xCAT2.11, XCAT offers a new version of mlnxofed_ib_install(i.e. mlnxofed_ib_install.v2).  From the perspective of function, the v2 is forward compatible with v1. But the v2 has different usage interface from v1. it becomes more flexible. we still ship v1 with XCAT but stop support it from xCAT2.11. We recommend using mlnxofed_ib_install.v2.

No matter which one you choose, you should copy it into ``/install/postscripts`` before using, such as ::

	cp /opt/xcat/share/xcat/ib/scripts/Mellanox/mlnxofed_ib_install.v2 /install/postscripts/mlnxofed_ib_install
	

Mellanox provides different OFED ISOs, named like MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso, to contain IB drivers/libraries needed by different operating system. No matter which version of sample postscript you choose, you should prepare correct Mellanox OFED ISO ahead by yourslef. 

**[NOTE]** Mellanox also provides OFED files with tarball format, but for XCAT, we just support ISO format right now.  
	
The Usage of Sample Postscript Version 2
""""""""""""""""""""""""""""""""""""""""

Obtain the Mellanox OFED ISO file and put it under the /install directory following the xCAT directory structure: ``/install/post/otherpkgs/<osver>/<arch>/ofed`` .

When you use mlnxofed_ib_install.v2, no matter for diskfull or diskless installation, some options should be assigned in the command line argument way.
These options are:

* **-ofeddir** : the directory where OFED ISO file is saved. this is necessary option no matter for diskfull or diskless installation
* **-ofedname**: the name of OFED ISO file. this is necessary option no matter for diskfull or diskless installation
* **-passmlnxofedoptions**: The mlnxofed_ib_install invokes the perl script mlnxofedinstall from Mellanox OFED ISO. If you want to pass the argument to mlnxofedinstall, using this option. if you don't assign any argument, defualt value are --without-32bit --without-fw-update --force". In order to distinguish which argument are passed to mlnxofedinstall and which options are belong to mlnxofed_ib_install.v2, any argument wanted to passed to mlnxofedinstall must follow behind -passmlnxofedoptions and end with "-end-",
* **-installroot**: the image root path. this is necessary attribute in diskless scenario
* **-nodesetstate**: nodeset status, the value are install, boot or genimage. this is necessary attribute in diskless scenario

For example, if you use MLNX_OFED_LINUX-3.1-1.0.0-ubuntu14.04-ppc64le.iso and save it under ``/install/post/otherpkgs/ubuntu14.04.3/ppc64le/ofed/`` , you want to pass ``--without-32bit --without-fw-update --add-kernel-support --force`` to mlnxofedinstall. you can use like below ::

    mlnxofed_ib_install -ofeddir /install/post/otherpkgs/ubuntu14.04.3/ppc64le/ofed/ -passmlnxofedoptions --without-32bit --without-fw-update --add-kernel-support --force -end- -ofedname MLNX_OFED_LINUX-3.1-1.0.0-ubuntu14.04-ppc64le.iso


The Usage of Sample Postscript Version 1(Don't recommend to use)
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

Prepare Mellanox OFED ISO file and mount it onto suggested target location on the XCAT MN according your OS and ARCH: ::

    mkdir -p /install/post/otherpkgs/<osver>/<arch>/ofed
    mount -o loop MLNX_OFED_LINUX-<packver1>-<packver2>-<osver>-<arch>.iso /install/post/otherpkgs/<osver>/<arch>/ofed

Take sles11 sp1 for x86_64 as an example ::

	mkdir -p /install/post/otherpkgs/sles11.1/x86_64/ofed/
	mount -o loop MLNX_OFED_LINUX-1.5.3-3.0.0-sles11sp1-x86_64.iso /install/post/otherpkgs/sles11.1/x86_64/ofed/
		
Take Ubuntu14.4.1 for p8le as an example ::

	mkdir -p /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed
	mount -o loop MLNX_OFED_LINUX-2.3-1.0.1-ubuntu14.04-ppc64le.iso /install/post/otherpkgs/ubuntu14.04.1/ppc64el/ofed

	
The mlnxofed_ib_install invokes the perl script mlnxofedinstall from Mellanox OFED ISO. If you want to pass the argument of mlnxofedinstall, you set the argument to the environment variable mlnxofed_options which could be read by mlnxofed_ib_install. For example: PPE requires the 32-bit version of libibverbs, but the default mlnxofed_ib_install will remove all the old ib related packages at first including the 32-bit version of libibverbs. In this case, you can set the environment variable ``mlnxofed_options=--force`` when running the mlnxofed_ib_install. For diskfull, you should put the environment variable ``mlnxofed_options=--force`` in mypostscript.tmpl. myposcript.tmpl is in ``/opt/xcat/share/xcat/templates/mypostscript/`` by default. When customize it, you should copy it into ``/install/postscripts/myposcript.tmpl`` ::

	mlnxofed_options='--force'
	export  mlnxofed_options
	
For diskless, you should put the variable before mlnxofed_ib_install in <profile>.postinstall ::

	installroot=$1 ofeddir=/install/post/otherpkgs/<osver>/<arch>/ofed/ NODESETSTATE=genimage  mlnxofed_options=--force /install/postscripts/mlnxofed_ib_install

	
Install IB Drives during Node installation
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Configuration for diskfull installation
"""""""""""""""""""""""""""""""""""""""
1. Set script ``mlnxofed_ib_install`` as postbootscript

If you use **mlnxofed_ib_install.v2**, usage likes below ::

	chdef <node> -p postbootscripts="mlnxofed_ib_install -ofeddir <the path of OFED ISO file> -passmlnxofedoptions <the args passed to mlnx> -end- -ofedname <OFED ISO file name>" 

If you use **mlnxofed_ib_install**, usage likes below ::

	chdef <node> -p postbootscripts=mlnxofed_ib_install
	
**[Note]** step 2-4 are only needed by RHEL and SLES

2. Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/install/<ostype>/compute.<osver>.<arch>.pkglist /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

3. Edit your /install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist and add ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

4. Make sure the related osimage use the customized pkglist ::

	lsdef -t osimage -o <osver>-<arch>-install-compute

if not, change it ::

	chdef -t osimage -o <osver>-<arch>-install-compute  pkglist=/install/custom/install/<ostype>/compute.<osver>.<arch>.pkglist

5. Install node ::

	nodeset <node> osimage=<osver>-<arch>-install-compute
	rsetboot <node> net
	rpower <node> reset

Configuration for diskless installation
"""""""""""""""""""""""""""""""""""""""

**[Note]** step 1 is only need by RHEL and SLES

1. Copy the pkglist to the custom directory ::

	cp /opt/xcat/share/xcat/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist

Edit your ``/install/custom/netboot/<ostype>/<profile>.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/<ostype>/ib.<osver>.<arch>.pkglist#

Take sles11 sp1 on x86_64 for example, Edit the ``/install/custom/netboot/sles11.1/x86_64/compute/compute.sles11.1.x86_64.pkglist`` and add: ::

	#INCLUDE:/opt/xcat/share/xcat/ib/netboot/sles/ib.sles11.1.x86_64.pkglist#

2. Prepare postinstall scripts ::

	mkdir -p /install/custom/netboot/<ostype>/
	cp /opt/xcat/share/xcat/netboot/<ostype>/<profile>.postinstall /install/custom/netboot/<ostype>/
	chmod +x /install/custom/netboot/<ostype>/<profile>.postinstall
	
Edit ``/install/custom/netboot/<ostype>/<profile>.postinstall`` and add: ::

    /install/postscripts/mlnxofed_ib_install -ofeddir <the path of OFED ISO file> -ofedname <OFED ISO file name> -nodesetstate genimage  -installroot $1
		
3. Set the related osimage use the customized pkglist and customized compute.postinsall ::

	chdef  -t osimage -o <osver>-<arch>-netboot-compute \
		pkglist=/install/custom/netboot/<ostype>/compute.<osver>.<arch>.pkglist \
		postinstall=/install/custom/netboot/<ostype>/<profile>.postinstall

**[Note]** Ubuntu doesn't need pkglist attribute.

4. Generate and package image for diskless installation ::

	genimage   <osver>-<arch>-netboot-compute 
	packimage  <osver>-<arch>-netboot-compute

5. Install node ::

	nodeset <nodename> osimage=<osver>-<arch>-netboot-compute 
	rsetboot <nodename> net
	rpower <nodename> reset


Mellanox IB Interface Configuration
-----------------------------------
XCAT provided two sample postscripts - configiba.1port and configiba.2ports to configure the IB secondary adapter before xcat 2.8, these tow scripts still work but will be in maintenance mode. 

A new postscript ``/install/postscripts/configib`` is shipped with XCAT 2.8, the configib postscript works with the new "nics" table and confignic postscript which where introduced in XCAT 2.8 also. xcat recommends you to use new configib script from now on.

IB Interface is a kind of additional adapters for Xcat, so the process of configuring Mellanox IB interface complies with the process of Configure Additional Network Interfaces

Below are an simple example to configure Mellanox IB in ubuntu14.4.1 on p8le

If your target Mellanox IB adapter has 2 ports, and you plan to give port ib0 4 different IPs, 2 are IPV4 (20.0.0.3 and 30.0.0.3) and another 2 are IPV6 (1:2::3 and 2:2::3).

1. Define your networks in networks table ::

	chdef -t network -o ib0ipv41 net=20.0.0.0 mask=255.255.255.0 mgtifname=ib0 
	chdef -t network -o ib0ipv42 net=30.0.0.0 mask=255.255.255.0 mgtifname=ib0
	chdef -t network -o ib0ipv61 net=1:2::/64 mask=/64 mgtifname=ib0 gateway=1:2::2
	chdef -t network -o ib0ipv62 net=2:2::/64 mask=/64 mgtifname=ib0 gateway=

2. Define IPs for ib0 ::

	chdef <node> nicips.ib0="20.0.0.3|30.0.0.3|1:2::3|2:2::3" nicnetworks.ib0="ib0ipv41|ib0ipv42|ib0ipv61|ib0ipv62" nictypes.ib0="Infiniband"

3. Configure ib0 ::

	updatenode <node> -P "confignics --ibaports=2"


Mellanox Switch Configuration
-----------------------------

Setup the XCAT Database
^^^^^^^^^^^^^^^^^^^^^^^
The Mellanox Switch is only supported in XCAT Release 2.7 or later.

Add the switch ip address in the ``/etc/hosts`` file

Define IB switch as a node: ::

	chdef -t node -o mswitch groups=all nodetype=switch mgt=switch

Add the login user name and password to the switches table: ::

	tabch switch=mswitch switches.sshusername=admin switches.sshpassword=admin switches.switchtype=MellanoxIB

The switches table will look like this: ::

	#switch,...,sshusername,sshpassword,switchtype,....  
	"mswitch",,,,,,,"admin","admin","MellanoxIB",,

If there is only one admin and one password for all the switches then put the entry in the XCAT passwd table for the admin id and password to use to login. ::

	tabch key=mswitch  passwd.username=admin passwd.password=admin

The passwd table will look like this: ::

	#key,username,password,cryptmethod,comments,disable
	"mswitch","admin","admin",,,

Setup ssh connection to the Mellanox Switch
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To run commands like xdsh and script to the Mellanox Switch, we need to setup ssh to run without prompting for a password to the Mellanox Switch. To do this, first you must add a configuration file. This configuration file is NOT needed for XCAT 2.8 and later. ::

	mkdir -p /var/opt/xcat/IBSwitch/Mellanox
	cd /var/opt/xcat/IBSwitch/Mellanox
	cp /opt/xcat/share/xcat/devicetype/IBSwitch/Mellanox/config .

The file contains the following: ::

	[main]
	[xdsh]
	pre-command=cli
	post-command=NULL

Then run the following: ::

	rspconfig mswitch sshcfg=enable

**[Note]** For Mellanox switch in manufacturing defaults status, the user need to answer 'no' for the initial configuration wizard prompt as follows before run 'rspconfig'. ::

	[s1mn][/](/)> ssh -l admin mswitch
	Mellanox MLNX-OS Switch Management
	Password:
	Last login: Wed Feb 20 20:09:50 2013 from 1.2.3.4
	Mellanox Switch
	Mellanox configuration wizard
	Do you want to use the wizard for initial configuration? **no**
	To return to the wizard from the CLI, enter the "configuration jump-start"
	command from configure mode. Launching CLI...
	switch-xxxxxx [standalone: unknown] > exit

Setup syslog on the Switch
^^^^^^^^^^^^^^^^^^^^^^^^^^

Use the following command to consolidate the syslog to the Management Node or Service Nodes, where ip is the addess of the MN or SN as known by the switch. ::

	rspconfig mswitch logdest=<ip>

Configure xdsh for Mellanox Switch
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
To run xdsh commands to the Mellanox Switch, you must use the --devicetype input flag to xdsh. In addition, for XCAT versions less than 2.8, you must add a configuration file, please see **"Setup ssh connection to the Mellanox Switch"** section.

For the Mellanox Switch the --devicetype is "IBSwitch::Mellanox". See xdsh man page: `http://xcat.sourceforge.net/man1/xdsh.1.html <http://xcat.sourceforge.net/man1/xdsh.1.html>`_ for details.

Now you can run the switch commands from the mn using xdsh. For example: ::

	xdsh mswitch -l admin --devicetype IBSwitch::Mellanox 'enable;configure terminal;show ssh server host-keys'

Commands Supported for the Mellanox Switch
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

Setup the snmp alert destination: ::

	rspconfig <switch> snmpdest=<ip> [remove]

where "remove" means to remove this ip from the snmp destination list.

Enable/disable setting the snmp traps. ::

	rspconfig <switch> alert=enable/disable

Define the read only community for snmp version 1 and 2. ::

	rspconfig <switch> community=<string>

Enable/disable snmp function on the swithc. ::

    rspconfig <switch> snmpcfg=enable/disable

Enable/disable ssh-ing to the switch without password. ::

    rspconfig <switch> sshcfg=enable/disable

Setup the syslog remove receiver for this switch, and also define the minimum level of severity of the logs that are sent. The valid levels are: emerg, alert, crit, err, warning, notice, info, debug, none, remove. "remove" means to remove the given ip from the receiver list. ::

    rspconfig <switch> logdest=<ip> [<level>]

For doing other tasks on the switch, use xdsh. For example: ::

    xdsh mswitch -l admin --devicetype IBSwitch::Mellanox  'show logging'

Interactive commands are not supported by xdsh. For interactive commands, use ssh.

Send SNMP traps to XCAT Management Node
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
First, get `http://www.mellanox.com/related-docs/prod_ib_switch_systems/MELLANOX-MIB.zip <http://www.mellanox.com/related-docs/prod_ib_switch_systems/MELLANOX-MIB.zip>`_ , unzip it. Copy the mib file MELLANOX-MIB.txt to ``/usr/share/snmp/mibs`` directory on the mn and sn (if the sn is the snmp trap destination.)

Then,

To configure, run: ::

	monadd snmpmon
	moncfg snmpmon <mswitch>

To start monitoring, run:  ::

	monstart snmpmon <mswitch>

To stop monitoring, run: ::

	monstop snmpmon <mswitch>

To deconfigure, run: ::

	mondecfg snmpmon <mswitch>

For more details on monitoring the cluster:
`Monitoring_an_xCAT_Cluster/#snmp-monitoring <http://sourceforge.net/p/xcat/wiki/Monitoring_an_xCAT_Cluster/#snmp-monitoring>`_

UFM Configuration
-----------------

UFM server are just regular Linix boxes with UFM installed. XCAT can help install and configure the UFM servers. The XCAT mn can send remote command to UFM through xdsh. It can also collect SNMP traps and syslogs from the UFM servers.

Setup xdsh to UFM and backup
^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Assume we have two hosts with UFM installed, called host1 and host2. First define the two hosts in the XCAT cluster. Usually the network that the UFM hosts are in a different than the compute nodes, make sure to assign correct servicenode and xcatmaster in the noderes table. And also make sure to assign correct os and arch values in the nodetype table for the UFM hosts. For example: ::

	mkdef -t node -o host1,host2 groups=ufm,all os=sles11.1 arch=x86_64 servicenode=10.0.0.1 xcatmaster=10.0.0.1

Then exchange the SSH key so that it can run xdsh. ::

	xdsh host1,host2 -K

Now we can run xdsh on the UFM hosts. ::

	xdsh ufm date

Consolidate syslogs
^^^^^^^^^^^^^^^^^^^
Run the following command to make the UFM hosts to send the syslogs to the XCAT mn:  ::

	updatenode ufm -P syslog

To test, run the following commands on the UFM hosts and see if the XCAT MN receives the new messages in /var/log/messages  ::

	logger xCAT "This is a test"


Send SNMP traps to XCAT Management Node
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
You need to have the Advanced License for UFM in order to send SNMP traps.

1. Copy the mib file to ``/usr/share/snmp/mibs`` directory on the mn. ::

	scp ufmhost:/opt/ufm/files/conf/vol_ufm3_0.mib /usr/share/snmp/mibs

Where ufmhost is the host where UFM is installed.

2. On the UFM host, open the /opt/ufm/conf/gv.cfg configuration file. Under the [Notifications] line, set ::

	snmp_listeners = <IP Address 1>[:<port 1>][,<IP Address 2>[:<port 2>].]

the default port is 162. For example: ::

	ssh ufmhost
	vi /opt/ufm/conf/gv.cfg
	
	....
	[Notifications]
	snmp_listeners = 10.0.0.1

where 10.0.0.1 is the the ip address of the management node.

3. On the UFM host, restart the ufmd ::

	service ufmd restart

4. From UFM GUI, click on the "Config" tab; bring up the "Event Management" Policy Table. Then select the SNMP check boxes for the events you are interested in to enable the system to send an SNMP traps for these events. Click "OK".

5. Make sure snmptrapd is up and running on mn and all monitoring servers.

It should have the '-m ALL' flag. ::

	ps -ef |grep snmptrapd
	root 31866 1 0 08:44 ? 00:00:00 /usr/sbin/snmptrapd -m ALL

If it is not running, then run the following commands: ::

	monadd snmpmon
	monstart snmpmon


Mellanox Switch and Adapter Firmware Update
-------------------------------------------

Adapter Firmware Update
^^^^^^^^^^^^^^^^^^^^^^^

Please download the OFED IB adapter firmware from the Mellanox site `http://www.mellanox.com/page/firmware_table_IBM <http://www.mellanox.com/page/firmware_table_IBM>`_ .

Linux OS image
""""""""""""""

Obtain device id:  ::

	lspci | grep -i mel

Check current installed fw level: ::

	mstflint -d 0002:01:00.0 q | grep FW

Copy or mount firmware to host:

Burn new firmware on each ibaX: ::

	mstflint -d 0002:01:00.0 -i <image location> b

Note: if this is a PureFlex MezzanineP adapater then you must select the correct image for each ibaX device. Note the difference in the firmware image at end of filename: _0.bin (iba0/iba2) & _1.bin (iba1/iba3)

Verify download successful: ::

	mstflint -d 0002:01:00.0 q

Activate the new firmware: ::

	reboot the image

Note: the above 0002:01:00.0 device location was used as an example only. it is not meant to imply that there is only one device location or that your device will have the same device location.

Mellanox Switch Firmware Upgrade
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

This section provides manual procedure to help update the firmware for Mellanox Infiniband (IB) Switches. You can down load IB switch firmware like IB6131 (image-PPC_M460EX-SX_3.2.xxx.img) from the Mellanox website `http://www.mellanox.com/page/firmware_table_IBM <http://www.mellanox.com/page/firmware_table_IBM>`_ and place into your XCAT Management Node or server that can communicate to Flex IB6131 switch module. There are two ways to update the MLNX-OS switch package. This process works regardless if updating an internal PureFlex chassis Infiniband switch (IB6131 or for an external Mellanox switch.

Update via Browser
""""""""""""""""""

This method is straight forward if your switches are on the public network or your browser is already capable to tunnel to the private address. If neither is the case then you may prefer to use option two.

After logging into the switch (id=admin, pwd=admin)

Select the "System" tab and then the "MLNX-OS Upgrade" option

Under the "Install New Image", select the "Install via scp"
URL: scp://userid@fwhost/directoryofimage/imagename

Select "Install Image"

The image will then be downloaded to the switch and the installation process will begin.

Once completed, the switch must be rebooted for the new package to be activate

Firmware Update using CLI
"""""""""""""""""""""""""

Login to the IB switch: ::

	ssh admin@<switchipaddr>
	enable  (get into correct CLI mode. You can use en)
	configure terminal (get into correct CLI mode. You can use co t)

List current images and Remove older images to free up space: ::

	show image
	image delete <ibimage>
	(you can paste in ibimage name from show image for image delete)

Get the new IB image using fetch with scp to a server that contains new IB image. An example of IB3161 image would be "image-PPC_M460EX-SX_3.2.0291.img" Admin can use different protocol . This image fetch scp command is about 4 minutes. ::

	image fetch ?
	image fetch scp://userid:password@serveripddr/<full path ibimage location>

Verify that new IB image is loaded, then install the new showIB image on IB switch. The install image process goes through 4 stages Verify image, Uncompress image, Create Filesystems, and Extract Image. This install process takes about 9 minutes. ::

	show image
	image install <newibimage>
	(you can paste in new IB image from "show image" to execute image install)

Toggle boot partition to new IB image, verify image install is loaded , and that next boot setting is pointing to new IB image. ::

	image boot next
	show image

Save the changes made for new IB image: ::

	configuration write

Activate the new IB image (reboot switch): ::
      
	reload


