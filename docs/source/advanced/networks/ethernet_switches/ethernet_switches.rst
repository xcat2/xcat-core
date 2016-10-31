Configure Ethernet Switches
---------------------------

It is recommended that spanning tree be set in the switches to portfast or edge-port for faster boot performance. See the relevant switch documentation as to how to configure this item.

It is recommended that lldp protocol in the switches is enabled to collect the switch and port information for compute node during discovery process.

**Note**: this step is necessary if you want to use **xCAT**'s automatic switch-based discovery described in :doc:`switch-based discovery </guides/admin-guides/manage_clusters/ppc64le/discovery/switch_discovery>` for IPMI-controlled rack-mounted servers (Includes OpenPOWER server and x86_64 server) and Flex chassis. If you have a small cluster and prefer to use the sequential discover method described in :doc:`Sequential-based discovery </guides/admin-guides/manage_clusters/ppc64le/discovery/seq_discovery>` or manually enter the MACs for the hardware, you can skip this section. Although you may want to still set up your switches for management so you can use xCAT tools to manage them, as described in :ref:`Managing_Ethernet_Switches`.

xCAT will use the ethernet switches during node discovery to find out which switch port a particular MAC address is communicating over. This allows xCAT to match a random booting node with the proper node name in the database. To set up a switch, give it an IP address on its management port and enable basic **SNMP** functionality. (Typically, the **SNMP** agent in the switches is disabled by default.) The easiest method is to configure the switches to give the **SNMP** version 1 community string called "public" read access. This will allow xCAT to communicate to the switches without further customization. (xCAT will get the list of switches from the **switch** table.) If you want to use **SNMP** version 3 (e.g. for better security), see the example below. With **SNMP** V3 you also have to set the user/password and AuthProto (default is **md5**) in the switches table.

If for some reason you can't configure **SNMP** on your switches, you can use sequential discovery or the more manual method of entering the nodes' MACs into the database. 

**SNMP** V3 Configuration example:   

xCAT supports many switch types, such as **BNT** and **Cisco**. Here is an example of configuring **SNMP V3** on the **Cisco** switch 3750/3650:

#. First, user should switch to the configure mode by the following commands: ::

    [root@x346n01 ~]# telnet xcat3750
    Trying 192.168.0.234...
    Connected to xcat3750.
    Escape character is '^]'.
    User Access Verification
    Password:

    xcat3750-1>enable
    Password:

    xcat3750-1#configure terminal
    Enter configuration commands, one per line.  End with CNTL/Z.
    xcat3750-1(config)#

#. Configure the **snmp-server** on the switch: ::

    Switch(config)# access-list 10 permit 192.168.0.20    # 192.168.0.20 is the IP of MN
    Switch(config)# snmp-server group xcatadmin v3 auth write v1default
    Switch(config)# snmp-server community public RO 10
    Switch(config)# snmp-server community private RW 10
    Switch(config)# snmp-server enable traps

#. Configure the **snmp** user id (assuming a user/pw of xcat/passw0rd): ::

    Switch(config)# snmp-server user xcat xcatadmin v3 auth SHA passw0rd access 10

#. Check the **snmp** communication to the switch : ::

    On the MN: make sure the snmp rpms have been installed. If not, install them:

    yum install net-snmp net-snmp-utils

    Run the following command to check that the snmp communication has been setup successfully (assuming the IP of the switch is 192.168.0.234):

    snmpwalk -v 3 -u xcat -a SHA -A passw0rd -X cluster -l authnoPriv 192.168.0.234 .1.3.6.1.2.1.2.2.1.2

Later on in this document, it will explain how to make sure the switch and switches tables are setup correctly.

.. _Managing_Ethernet_Switches:

Switch Management
-----------------

When managing Ethernet switches, the admin often logs into the switches one by one using SSH or Telnet and runs the switch commands. However, it becomes time consuming when there are a lot of switches in a cluster. In a very large cluster, the switches are often identical and the configurations are identical. It helps to configure and monitor them in parallel from a single command.

For managing Mellanox IB switches and  Qlogic IB switches, see :doc:`Mellanox IB switches and Qlogic IB switches </advanced/networks/infiniband/index>` 

xCAT will not do a lot of switch management functions. Instead, it will configure the switch so that the admin can run remote command such as ``xdsh`` for it. Thus, the admin can use the ``xdsh`` to run proprietary switch commands remotely from the xCAT mn to enable **VLAN**, **bonding**, **SNMP** and others.

Running Remote Commands in Parallel
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

You can use xdsh to run parallel commands on Ethernet switches. The following shows how to configure xCAT to run xdsh on the switches: 

**[Note]**:Configure the switch to allow **ssh** or **telnet**. This varies for switch to switch. Refer to the switch command references to find out how to do it.

Add the switch in xCAT DB. Refer to the "Discovering Switches" section if you want xCAT to discover and define the switches for you. ::

     mkdef bntc125 groups=switch mgt=switch ip=10.4.25.1 nodetype=switch switchtype=BNT

Set the ssh or telnet username an d password. ::

       chdef bntc125 username=admin \
                     password=password \
                     protocol=ssh
       or 
       chdef bntc125 username=admin \
                     password=password \
                     protocol=telnet

   If there are a lot of switches and they have the same user name and password for ssh or telnet connection, you can put them in the passwd table keyed by **switch**. You can use the comments attribute to describe it is for ssh to telnet. The blank means ssh. ::

    #key,username,password,cryptmethod,authdomain,comments,disable
    "system","root","cluster",,,,
    "switch","admin","password",,,,

    Run xdsh command

    xdsh bntc125 --devicetype EthSwitch::BNT "enable;configure terminal;vlan 3;end;show vlan"

Note that you can run multiple switch commands, they are separated by comma.

Also note that --devicetype is used here. xCAT supports the following switch types out of the box: ::

             * BNT 
             * Cisco 
             * Juniper
             * Mellanox (for IB and Ethernet switches)

If you have different type of switches, you can either use the general flag

"--devicetype EthSwitch" or add your own switch types. (See the following section).

Here is what result will look like: ::

       bntc125: start SSH session...
       bntc125:  RS G8000&gt;enable
       bntc125:  Enable privilege granted.
       bntc125: configure terminal
       bntc125:  Enter configuration commands, one per line.  End with Ctrl/Z.
       bntc125: vlan 3
       bntc125: end
       bntc125: show vlan
       bntc125: VLAN                Name                Status            Ports
       bntc125:  ----  --------------------------------  ------  ------------------------ 
       bntc125:  1     Default VLAN                      ena     45-XGE4
       bntc125:  3     VLAN 3                            dis     empty
       bntc125:  101   xcatpriv101                       ena     24-44
       bntc125:  2047  9.114.34.0-pub                    ena     1-23 44

You can run ``xdsh`` against more than one switches at a time,just like running ``xdsh`` against nodes.

Use xcoll to summarize the result. For example: ::

      xdsh bntc1,bntc2 --devicetype EthSwitch::BNT  "show access-control" |xcoll

The output looks like this: ::

      ====================================
       bntc1,bntc2
      ====================================
      start Telnet session...
      terminal-length 0
      show access-control
      Current access control configuration:
         No ACLs configured.
         No IPv6 ACL configured.
         No ACL group configured.
         No VMAP configured.

Add New Switch Types
''''''''''''''''''''

For any new switch types that's not supported by xCAT yet, you can use the general **--device EthSwitch** flag with xdsh command. ::

       xdsh <switch_names> --devicetype EthSwitch "cmd1;cmd2..."

The only problem is that the page break is not handled well when the command output is long. To remove the page break, you can add a switch command that sets the terminal length to 0 before all other commands. ::

     xdsh <switch_names> --devicetype EthSwitch "command-to-set-term-length-to-0;cmd1;cmd2..."

     where command-to-set-term-length-to-0 is the command to set the terminal length to 0 so that the output does not have page breaks.

You can add this command to the configuration file to avoid specifying it for each xdsh by creating a new switch type. Here is what you do: ::

       cp /opt/xcat/share/xcat/devicetype/EthSwitch/Cisco/config \
           /var/opt/xcat/EthSwitch/XXX/config

where XXX is the name of the new switch type. You can give it any name.
Then add the command for set terminal length to 0 to the "pre-command" line.
The new configuration file will look like this: ::

      # cat /var/opt/xcat/EthSwitch/XXX/config
      [main]
      ssh-setup-command=
      [xdsh]
      pre-command=command-to-set-term-length-to-0;
      post-command=NULL

For **BNT** switches, the **command-to-set-term-length-to-0** is **terminal-length 0**.

Make sure to add a semi-colon at the end of the "pre-command" line.

Then you can run the xdsh like this: ::

       xdsh <switch_names> --devicetype EthSwitch::XXX "cmd1;cmd2..."


