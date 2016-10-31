IB Switch Configuration
=======================

Setup the xCAT Database
-----------------------

The Mellanox Switch is only supported in xCAT Release 2.7 or later.

Add the switch ip address in the ``/etc/hosts`` file

Define IB switch as a node: ::

	chdef -t node -o mswitch groups=all nodetype=switch mgt=switch

Add the login user name and password to the switches table: ::

	tabch switch=mswitch switches.sshusername=admin switches.sshpassword=admin switches.switchtype=MellanoxIB

The switches table will look like this: ::

	#switch,...,sshusername,sshpassword,switchtype,....  
	"mswitch",,,,,,,"admin","admin","MellanoxIB",,

If there is only one admin and one password for all the switches then put the entry in the xCAT passwd table for the admin id and password to use to login. ::

	tabch key=mswitch  passwd.username=admin passwd.password=admin

The passwd table will look like this: ::

	#key,username,password,cryptmethod,comments,disable
	"mswitch","admin","admin",,,

Setup ssh connection to the Mellanox Switch
-------------------------------------------

To run commands like xdsh and script to the Mellanox Switch, we need to setup ssh to run without prompting for a password to the Mellanox Switch. To do this, first you must add a configuration file. This configuration file is NOT needed for xCAT 2.8 and later. ::

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
--------------------------

Use the following command to consolidate the syslog to the Management Node or Service Nodes, where ip is the addess of the MN or SN as known by the switch. ::

	rspconfig mswitch logdest=<ip>

Configure xdsh for Mellanox Switch
----------------------------------
To run xdsh commands to the Mellanox Switch, you must use the --devicetype input flag to xdsh. In addition, for xCAT versions less than 2.8, you must add a configuration file, see `Setup ssh connection to the Mellanox Switch`_ section.

For the Mellanox Switch the ``--devicetype`` is ``IBSwitch::Mellanox``. See :doc:`xdsh man page </guides/admin-guides/references/man1/xdsh.1>` for details.

Now you can run the switch commands from the mn using xdsh. For example: ::

	xdsh mswitch -l admin --devicetype IBSwitch::Mellanox \
     'enable;configure terminal;show ssh server host-keys'

Commands Supported for the Mellanox Switch
------------------------------------------

Setup the snmp alert destination: ::

	rspconfig <switch> snmpdest=<ip> [remove]

where "remove" means to remove this ip from the snmp destination list.

Enable/disable setting the snmp traps. ::

	rspconfig <switch> alert=enable/disable

Define the read only community for snmp version 1 and 2. ::

	rspconfig <switch> community=<string>

Enable/disable snmp function on the switch. ::

    rspconfig <switch> snmpcfg=enable/disable

Enable/disable ssh-ing to the switch without password. ::

    rspconfig <switch> sshcfg=enable/disable

Setup the syslog remove receiver for this switch, and also define the minimum level of severity of the logs that are sent. The valid levels are: emerg, alert, crit, err, warning, notice, info, debug, none, remove. "remove" means to remove the given ip from the receiver list. ::

    rspconfig <switch> logdest=<ip> [<level>]

For doing other tasks on the switch, use xdsh. For example: ::

    xdsh mswitch -l admin --devicetype IBSwitch::Mellanox  'show logging'

Interactive commands are not supported by xdsh. For interactive commands, use ssh.

Send SNMP traps to xCAT Management Node
---------------------------------------

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

For more details on monitoring the cluster: TODO
`Monitoring_an_xCAT_Cluster/#snmp-monitoring <http://sourceforge.net/p/xcat/wiki/Monitoring_an_xCAT_Cluster/#snmp-monitoring>`_
