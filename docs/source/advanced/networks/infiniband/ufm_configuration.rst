UFM Configuration
=================


UFM server are just regular Linux boxes with UFM installed. xCAT can help install and configure the UFM servers. The XCAT mn can send remote command to UFM through xdsh. It can also collect SNMP traps and syslogs from the UFM servers.

Setup xdsh to UFM and backup
----------------------------

Assume we have two hosts with UFM installed, called host1 and host2. First define the two hosts in the xCAT cluster. Usually the network that the UFM hosts are in a different than the compute nodes, make sure to assign correct servicenode and xcatmaster in the noderes table. And also make sure to assign correct os and arch values in the nodetype table for the UFM hosts. For example: ::

	mkdef -t node -o host1,host2 groups=ufm,all os=sles11.1 arch=x86_64 servicenode=10.0.0.1 xcatmaster=10.0.0.1

Then exchange the SSH key so that it can run xdsh. ::

	xdsh host1,host2 -K

Now we can run xdsh on the UFM hosts. ::

	xdsh ufm date

Consolidate syslogs
-------------------

Run the following command to make the UFM hosts to send the syslogs to the xCAT mn:  ::

	updatenode ufm -P syslog

To test, run the following commands on the UFM hosts and see if the xCAT MN receives the new messages in /var/log/messages  ::

	logger xCAT "This is a test"


Send SNMP traps to xCAT Management Node
---------------------------------------

You need to have the Advanced License for UFM in order to send SNMP traps.

1. Copy the mib file to ``/usr/share/snmp/mibs`` directory on the mn. ::

	scp ufmhost:/opt/ufm/files/conf/vol_ufm3_0.mib /usr/share/snmp/mibs

Where ufmhost is the host where UFM is installed.

2. On the UFM host, open the /opt/ufm/conf/gv.cfg configuration file. Under the [Notifications] line, set ::

	snmp_listeners = <IP Address 1>[:<port 1>][,<IP Address 2>[:<port 2>].]

The default port is 162. For example: ::

	ssh ufmhost
	vi /opt/ufm/conf/gv.cfg
	
	....
	[Notifications]
	snmp_listeners = 10.0.0.1

Where 10.0.0.1 is the the ip address of the management node.

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

	