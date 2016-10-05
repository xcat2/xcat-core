.. _Using-Postscript-label:

Using Postscript
----------------

xCAT automatically runs a few postscripts and postbootscripts that are delivered with xCAT to set up the nodes. You can also add your own scripts to further customize the nodes. This explains the xCAT support to do this.

Types of scripts
~~~~~~~~~~~~~~~~

There are two types of scripts in the postscripts table ( postscripts and postbootscripts). The types are based on when in the install process they will be executed. Run the following for more information:  

    ``man postscripts``

* **postscripts attribute** - List of scripts that should be run on this node after diskful installation or diskless boot.

           * **[RHEL]**

           Postscripts will be run before the reboot.
           
           * **[SLES]**

           Postscripts will be run after the reboot but before the init.d process. For Linux diskless deployment, the postscripts will be run at the init.d time, and xCAT will automatically add the list of postscripts from the postbootscripts attribute to run after postscripts list.

* **postbootscripts attribute** - list of postbootscripts that should be run on this Linux node at the init.d time after diskful installation reboot or diskless boot
* **xCAT**, by default, for diskful installs only runs the postbootscripts on the install and not on reboot. In xCAT a site table attribute runbootscripts is available to change this default behavior. If set to yes, then the postbootscripts will be run on install and on reboot. 
 
**xCAT automatically adds the postscripts from the xcatdefaults.postscripts attribute of the table to run first on the nodes after install or diskless boot.**

Adding your own postscripts
~~~~~~~~~~~~~~~~~~~~~~~~~~~

To add your own script, place it in /install/postscripts on the management node. Make sure it is executable and world readable. Then add it to the postscripts table for the group of nodes you want it to be run on (or the "all" group if you want it run on all nodes in the appropriate attribute, according to when you want it to run).

To check what scripts will be run on your node during installation: ::

       lsdef node1 | grep scripts
       postbootscripts=otherpkgs 
       postscripts=syslog,remoteshell,syncfiles

You can pass parameters to the postscripts. For example: ::

      script1 p1 p2,script2,....



p1 p2 are the parameters to script1.

Postscripts could be placed in the subdirectories in /install/postscripts on management node, and specify "subdir/postscriptname" in the postscripts table to run the postscripts in the subdirectories. This feature could be used to categorize the postscripts for different purposes. Here is an example: ::
     
       mkdir -p /install/postscripts/subdir1
       mkdir -p /install/postscripts/subdir2
       cp postscript1 /install/postscripts/subdir1/
       cp postscript2 /install/postscripts/subdir2/
       chdef node1 -p postscripts=subdir1/postscript1,subdir2/postscript2
       updatenode node1 -P

If some of your postscripts will affect the network communication between the management node and compute node, like restarting network or configuring bond, the postscripts execution might not be able to be finished successfully because of the network connection problems, even if we put this postscript be the last postscript in the list, xCAT still may not be able to update the node status to be "booted". The recommendation is to use the Linux "at" mechanism to schedule this network-killing postscript to be run at a later time. Here is an example:

The user needs to add a postscript to customize the nics bonding setup, the nics bonding setup will break the network between the management node and compute node, then we could use "at" to run this nic bonding postscripts after all the postscripts processes have been finished.

We could write a script, say, /install/postscripts/nicbondscript, the nicbondscript simply calls the confignicsbond using **"at"**: ::

       [root@xcatmn ~]#cat /install/postscripts/nicbondscript

       #!/bin/bash

       at -f ./confignicsbond now + 1 minute

       [root@xcatmn ~]#

Then :: 

       chdef <nodename> -p postbootscripts=nicbondscript

Recommended Postscript design
'''''''''''''''''''''''''''''


* Postscripts that you want to run anywhere, Linux, should be written in shell. This should be available on all OS's. If only on the service nodes, you can use Perl .
* Postscripts should log errors using the following command **local4** is the default xCAT syslog class. **logger -t xCAT -p local4.info "your info message**".
* Postscripts should have good and error exit codes (i.e 0 and 1).
* Postscripts should be well documented. At the top of the script, the first few lines should describe the function and inputs and output. You should have comments throughout the script. This is especially important if using regx.

PostScript/PostbootScript execution
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When your script is executed on the node, all the attributes in the site table are exported as variables for your scripts to use. You can add extra attributes for yourself. See the sample mypostscript file below.

To run the postscripts, a script is built, so the above exported variables can be input. You can usually find that script in /xcatpost on the node and for example in the Linux case it is call mypostscript. A good way to debug problems is to go to the node and just run mypostscript and see errors. You can also check the syslog on the Management Node for errors.

When writing you postscripts, it is good to follow the example of the current postscripts and write errors to syslog and in shell. See Suggestions for writing scripts.

All attributes in the site table are exported and available to the postscript/postbootscript during execution. See the mypostscript file, which is generated and executed on the nodes to run the postscripts.

Example of mypostscript  ::

    #subroutine used to run postscripts
    run_ps () {
    logdir="/var/log/xcat"
    mkdir -p $logdir
    logfile="/var/log/xcat/xcat.log"
    if [_-f_$1_]; then
     echo "Running postscript: $@" | tee -a $logfile
     ./$@ 2>&1 | tee -a $logfile
    else
     echo "Postscript $1 does NOT exist." | tee -a $logfile
    fi
    }
    # subroutine end
    AUDITSKIPCMDS='tabdump,nodels'
    export AUDITSKIPCMDS
    TEST='test'
    export TEST
    NAMESERVERS='7.114.8.1'
    export NAMESERVERS
    NTPSERVERS='7.113.47.250'
    export NTPSERVERS
    INSTALLLOC='/install'
    export INSTALLLOC
    DEFSERIALPORT='0'
    export DEFSERIALPORT
    DEFSERIALSPEED='19200'
    export DEFSERIALSPEED
    DHCPINTERFACES="'xcat20RRmn|eth0;rra000-m|eth1'"
    export DHCPINTERFACES
    FORWARDERS='7.113.8.1,7.114.8.2'
    export FORWARDERS
    NAMESERVER='7.113.8.1,7.114.47.250'
    export NAMESERVER
    DB='postg'
    export DB
    BLADEMAXP='64'
    export BLADEMAXP
    FSPTIMEOUT='0'
    export FSPTIMEOUT
    INSTALLDIR='/install'
    export INSTALLDIR
    IPMIMAXP='64'
    export IPMIMAXP
    IPMIRETRIES='3'
    export IPMIRETRIES
    IPMITIMEOUT='2'
    export IPMITIMEOUT
    CONSOLEONDEMAND='no'
    export CONSOLEONDEMAND
    SITEMASTER=7.113.47.250
    export SITEMASTER
    MASTER=7.113.47.250
    export MASTER
    MAXSSH='8'
    export MAXSSH
    PPCMAXP='64'
    export PPCMAXP
    PPCRETRY='3'
    export PPCRETRY
    PPCTIMEOUT='0'
    export PPCTIMEOUT
    SHAREDTFTP='1'
    export SHAREDTFTP
    SNSYNCFILEDIR='/var/xcat/syncfiles'
    export SNSYNCFILEDIR
    TFTPDIR='/tftpboot'
    export TFTPDIR
    XCATDPORT='3001'
    export XCATDPORT
    XCATIPORT='3002'
    export XCATIPORT
    XCATCONFDIR='/etc/xcat'
    export XCATCONFDIR
    TIMEZONE='America/New_York'
    export TIMEZONE
    USENMAPFROMMN='no'
    export USENMAPFROMMN
    DOMAIN='cluster.net'
    export DOMAIN
    USESSHONAIX='no'
    export USESSHONAIX
    NODE=rra000-m
    export NODE
    NFSSERVER=7.113.47.250
    export NFSSERVER
    INSTALLNIC=eth0
    export INSTALLNIC
    PRIMARYNIC=eth1
    OSVER=fedora9
    export OSVER
    ARCH=x86_64
    export ARCH
    PROFILE=service
    export PROFILE
    PATH=`dirname $0`:$PATH
    export PATH
    NODESETSTATE='netboot'
    export NODESETSTATE
    UPDATENODE=1
    export UPDATENODE
    NTYPE=service
    export NTYPE
    MACADDRESS='00:14:5E:5B:51:FA'
    export MACADDRESS
    MONSERVER=7.113.47.250
    export MONSERVER
    MONMASTER=7.113.47.250
    export MONMASTER
    OSPKGS=bash,openssl,dhclient,kernel,openssh-server,openssh-clients,busybox-anaconda,vim-
    minimal,rpm,bind,bind-utils,ksh,nfs-utils,dhcp,bzip2,rootfiles,vixie-cron,wget,vsftpd,ntp,rsync
    OTHERPKGS1=xCATsn,xCAT-rmc,rsct/rsct.core,rsct/rsct.core.utils,rsct/src,yaboot-xcat
    export OTHERPKGS1
    OTHERPKGS_INDEX=1
    export OTHERPKGS_INDEX
    export NOSYNCFILES
    # postscripts-start-here\n
    run_ps ospkgs
    run_ps script1 p1 p2
    run_ps script2
    # postscripts-end-here\n

The mypostscript file is generated according to the mypostscript.tmpl file.

.. _Using-the-mypostscript-template-label:

Using the mypostscript template
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Using the mypostscript template
'''''''''''''''''''''''''''''''

xCAT provides a way for the admin to customize the information that will be provided to the postscripts/postbootscripts when they run on the node. This is done by editing the mypostscript.tmpl file. The attributes that are provided in the shipped mypostscript.tmpl file should not be removed. They are needed by the default xCAT postscripts.

The mypostscript.tmpl, is shipped in the /opt/xcat/share/xcat/mypostscript directory.

If the admin customizes the mypostscript.tmpl, they should copy the mypostscript.tmpl to /install/postscripts/mypostscript.tmpl, and then edit it. The mypostscript for each node will be named mypostscript.<nodename>. The generated mypostscript.<nodename>. will be put in the /tftpboot/mypostscripts directory.

site table precreatemypostscripts attribute
'''''''''''''''''''''''''''''''''''''''''''

If the site table precreatemypostscripts attribute is set to 1 or yes, it will instruct xCAT at nodeset and updatenode time to query the db once for all of the nodes passed into the command and create the mypostscript file for each node and put them in a directory in $TFTPDIR(for example /tftpboot). The created mypostscript.<nodename>. file in the /tftpboot/mypostscripts directory will not be regenerated unless another nodeset or updatenode command is run to that node. This should be used when the system definition has stabilized. It saves time on the updatenode or reboot by not regenerating the mypostscript file.

If the precreatemyposcripts attribute is yes, and a database change is made or xCAT code is upgraded, then you should run a new nodeset or updatenode to regenerate the /tftpboot/mypostscript/mypostscript.<nodename>. file to pick up the latest database setting. The default for precreatemypostscripts is no/0.

When you run nodeset or updatenode, it will search the **/install/postscripts/mypostscript.tmpl** first. If the **/install/postscripts/mypostscript.tmpl** exists, it will use that template to generate the mypostscript for each node. Otherwise, it will use **/opt/xcat/share/xcat/mypostscript/mypostscript.tmpl**. 


Content of the template for mypostscript
''''''''''''''''''''''''''''''''''''''''

**The attributes that are defined in the shipped mypostscript.tmpl file** should not be removed. The xCAT default postscripts rely on that information to run successfully. **The following will explain the entries in the mypostscript.tmpl file**.

The SITE_TABLE_ALL_ATTRIBS_EXPORT line in the file directs the code to export all attributes defined in the site table. 
Note: the attributes are not always defined exactly as in the site table to avoid conflict with other table attributes of the same name. For example, the site table master attribute is named SITEMASTER in the generated mypostscript file. ::

        #SITE_TABLE_ALL_ATTRIBS_EXPORT#

The following line exports ENABLESSHBETWEENNODES by running the internal xCAT routine (enablesshbetweennodes). ::

       ENABLESSHBETWEENNODES=#Subroutine:xCAT::Template::enablesshbetweennodes:$NODE#
       export ENABLESSHBETWEENNODES

**tabdump(<TABLENAME>)** is used to get all the information in the **<TABLENAME>** table :: 

      tabdump(networks)

These line export the node name based on its definition in the database. ::

           NODE=$NODE
           export NODE

These lines get a comma separated list of the groups to which the node belongs. ::

    GROUP=#TABLE:nodelist:$NODE:groups#
    export GROUP

These lines reads the nodesres table, the given attributes (nfsserver,installnic,primarynic,xcatmaster,routenames) for the node **($NODE)**, and exports it. ::

     NFSSERVER=#TABLE:noderes:$NODE:nfsserver#
     export NFSSERVER
     INSTALLNIC=#TABLE:noderes:$NODE:installnic#
     export INSTALLNIC
     PRIMARYNIC=#TABLE:noderes:$NODE:primarynic#
     export PRIMARYNIC
     MASTER=#TABLE:noderes:$NODE:xcatmaster#
     export MASTER
     NODEROUTENAMES=#TABLE:noderes:$NODE:routenames#
     export NODEROUTENAMES

The following entry exports multiple variables from the routes table. Not always set. ::

     #ROUTES_VARS_EXPORT#

The following lines export nodetype table attributes. ::

     OSVER=#TABLE:nodetype:$NODE:os#
     export OSVER
     ARCH=#TABLE:nodetype:$NODE:arch#
     export ARCH
     PROFILE=#TABLE:nodetype:$NODE:profile#
     export PROFILE
     PROVMETHOD=#TABLE:nodetype:$NODE:provmethod#
     export PROVMETHOD

The following adds the current directory to the path for the postscripts. ::

     PATH=`dirname $0`:$PATH
     export PATH

The following sets the NODESETSTATE by running the internal xCAT getnodesetstate script. ::

     NODESETSTATE=#Subroutine:xCAT::Postage::getnodesetstate:$NODE#
     export NODESETSTATE

The following says the postscripts are not being run as a result of updatenode.(This is changed =1, when updatenode runs). ::

     UPDATENODE=0
     export UPDATENODE

The following sets the NTYPE to compute,service or MN. ::

     NTYPE=$NTYPE
     export NTYPE

The following sets the mac address. ::

     MACADDRESS=#TABLE:mac:$NODE:mac#
     export MACADDRESS

If vlan is setup, then the #VLAN_VARS_EXPORT# line will provide the following exports: ::

    VMNODE='YES'
    export VMNODE
    VLANID=vlan1...
    export VLANID
    VLANHOSTNAME=..
      ..
    #VLAN_VARS_EXPORT#

If monitoring is setup, then the #MONITORING_VARS_EXPORT# line will provide: ::

    MONSERVER=11.10.34.108
    export MONSERVER
    MONMASTER=11.10.34.108
    export MONMASTER
    #MONITORING_VARS_EXPORT#

The OSIMAGE_VARS_EXPORT# line will provide, for example: ::

     OSPKGDIR=/install/<os>/<arch>
     export OSPKGDIR
     OSPKGS='bash,nfs-utils,openssl,dhclient,kernel,openssh-server,openssh-clients,busybox,wget,rsyslog,dash,vim-minimal,ntp,rsyslog,rpm,rsync,
       ppc64-utils,iputils,dracut,dracut-network,e2fsprogs,bc,lsvpd,irqbalance,procps,yum'
     export OSPKGS

     #OSIMAGE_VARS_EXPORT#

THE NETWORK_FOR_DISKLESS_EXPORT# line will provide diskless networks information, if defined. ::

     NETMASK=255.255.255.0
     export NETMASK
     GATEWAY=8.112.34.108
     export GATEWAY
     ..
     #NETWORK_FOR_DISKLESS_EXPORT#

Note: the **#INCLUDE_POSTSCRIPTS_LIST#** and the **#INCLUDE_POSTBOOTSCRIPTS_LIST#** sections in **/tftpboot/mypostscript(mypostbootscripts)** on the Management Node will contain all the postscripts and postbootscripts defined for the node. When running an **updatenode** command for only some of the scripts , you will see in the **/xcatpost/mypostscript** file on the node, the list has been redefined during the execution of updatenode to only run the requested scripts. For example, if you run **updatenode <nodename> -P** syslog.

The **#INCLUDE_POSTSCRIPTS_LIST#** flag provides a list of postscripts defined for this **$NODE**. ::

    #INCLUDE_POSTSCRIPTS_LIST#

For example, you will see in the generated file the following stanzas: ::

    # postscripts-start-here
    # defaults-postscripts-start-here
    syslog
    remoteshell
    # defaults-postscripts-end-here
    # node-postscripts-start-here
    syncfiles
    # node-postscripts-end-here

The **#INCLUDE_POSTBOOTSCRIPTS_LIST#** provides a list of postbootscripts defined for this **$NODE**. ::

    #INCLUDE_POSTBOOTSCRIPTS_LIST#

For example, you will see in the generated file the following stanzas: ::

    # postbootscripts-start-here
    # defaults-postbootscripts-start-here
    otherpkgs
    # defaults-postbootscripts-end-here
    # node-postbootscripts-end-here
    # postbootscripts-end-here

Kinds of variables in the template
'''''''''''''''''''''''''''''''''''

**Type 1:** For the simple variable, the syntax is as follows. The mypostscript.tmpl has several examples of this. **$NODE** is filled in by the code. **UPDATENODE** is changed to 1, when the postscripts are run by ``updatenode``. **$NTYPE** is filled in as either compute,service or MN. ::

    NODE=$NODE
    export NODE
    UPDATENODE=0
    export UPDATENODE
    NTYPE=$NTYPE
    export NTYPE

**Type 2:** This is the syntax to get the value of one attribute from the **<tablename>** and its key is **$NODE**. It does not support tables with two keys. Some of the tables with two keys are **(litefile,prodkey,deps,monsetting,mpa,networks)**. ::

    VARNAME=#TABLE:tablename:$NODE:attribute#

For example, to get the new updatestatus attribute from the nodelist table: ::

    UPDATESTATUS=#TABLE:nodelist:$NODE:updatestatus#
    export UPDATESTATUS

**Type 3:** The syntax is as follows: ::

    VARNAME=#Subroutine:modulename::subroutinename:$NODE#
    or
    VARNAME=#Subroutine:modulename::subroutinename#

Examples in the mypostscript.tmpl are the following: ::

     NODESETSTATE=#Subroutine:xCAT::Postage::getnodesetstate:$NODE#
     export NODESETSTATE
     ENABLESSHBETWEENNODES=#Subroutine:xCAT::Template::enablesshbetweennodes:$NODE#
     export ENABLESSHBETWEENNODES

Note: Type 3 is not an open interface to add extensions to the template.

**Type 4:** The syntax is #FLAG#. When parsing the template, the code generates all entries defined by **#FLAG#**, if they are defined in the database. For example: To export all values of all attributes from the site table. The tag is ::

    #SITE_TABLE_ALL_ATTRIBS_EXPORT#

For the **#SITE_TABLE_ALL_ATTRIBS_EXPORT#** flag, the related subroutine will get the attributes' values and deal with the special case. such as : the site.master should be exported as **"SITEMASTER"**. And if the noderes.xcatmaster exists, the noderes.xcatmaster should be exported as **"MASTER"**, otherwise, we also should export site.master as the **"MASTER"**.

Other examples are: ::

    #VLAN_VARS_EXPORT#  - gets all vlan related items
    #MONITORING_VARS_EXPORT#  - gets all monitoring configuration and setup da ta
    #OSIMAGE_VARS_EXPORT# - get osimage related variables, such as ospkgdir, ospkgs ...
    #NETWORK_FOR_DISKLESS_EXPORT# - gets diskless network information
    #INCLUDE_POSTSCRIPTS_LIST# - includes the list of all postscripts for the node
    #INCLUDE_POSTBOOTSCRIPTS_LIST# - includes the list of all postbootscripts for the node

Note: Type4 is not an open interface to add extensions to the templatel.

**Type 5:** Get all the data from the specified table. The **<TABLENAME>** should not be a node table, like nodelist. This should be handles with TYPE 2 syntax to get specific attributes for the **$NODE**. tabdump would result in too much data for a nodetype table. Also the auditlog, eventlog should not be in tabdump for the same reason. site table should not be specified, it is already provided with the **#SITE_TABLE_ALL_ATTRIBS_EXPORT#** flag. It can be used to get the data from the two key tables (like switch). ::

  The syntax is: 

  tabdump(<TABLENAME>)

Edit mypostscript.tmpl
'''''''''''''''''''''''

**Add new attributes into mypostscript.tmpl**

When you add new attributes into the template, you should edit the **/install/postscripts/mypostscript.tmpl** which you created by copying **/opt/xcat/share/xcat/mypostscript/mypostscript.tmpl**. Make all additions before the **# postscripts-start-here** section. xCAT will first look in **/install/postscripts/mypostscript.tmpl** for a file and then if not found will use the one in **/opt/xcat/share/xcat/mypostcript/mypostscript.tmpl**.

For example: ::

    UPDATESTATUS=#TABLE:nodelist:$NODE:updatestatus#
    export UPDATESTATUS
    ...
    # postscripts-start-here
    #INCLUDE_POSTSCRIPTS_LIST#
    ## The following flag postscripts-end-here must not be deleted.
    # postscripts-end-here

Note: If you have a hierarchical cluster, you must copy your new mypostscript.tmpl to **/install/postscripts/mypostscript.tmpl** on the service nodes, unless **/install/postscripts** directory is mounted from the MN to the service node.

**Remove attribute from mypostscript.tmpl**

If you want to remove an attribute that you have added, you should remove all the related lines or comment them out with ##. For example, comment out the added lines. ::

    ##UPDATESTATUS=#TABLE:nodelist:$NODE:updatestatus#
    ##export UPDATESTATUS

Test the new template
''''''''''''''''''''''

There are two quick ways to test the template. 

#.
If the node is up: :: 

   updatenode <nodename> -P syslog

Check your generated template : ::

   Check the generated mypostscript file on compute node /xcatpost.

#.
Another way, is set the precreate option ::

    chdef -t site -o clustersite precreatemypostscripts=1

Then run ::

    nodeset <nodename> ....

Check your generated template ::

    vi /tftpboot/mypostscripts/mypostscript.<nodename>

Sample /xcatpost/mypostscript
'''''''''''''''''''''''''''''''

This is an example of the generated postscript for a servicenode install. It is found in /xcatpost/mypostscript on the node. ::

    # global value to store the running status of the postbootscripts,the value
    #is non-zero if one postbootscript failed
    return_value=0
    # subroutine used to run postscripts
    run_ps () {
     local ret_local=0
     logdir="/var/log/xcat"
     mkdir -p $logdir
     logfile="/var/log/xcat/xcat.log"
     if [ -f $1 ]; then
      echo "`date` Running postscript: $@" | tee -a $logfile
      #./$@ 2>&1 1> /tmp/tmp4xcatlog
      #cat /tmp/tmp4xcatlog | tee -a $logfile
      ./$@ 2>&1 | tee -a $logfile
      ret_local=${PIPESTATUS[0]}
      if [ "$ret_local" -ne "0" ]; then
        return_value=$ret_local
      fi
      echo "Postscript: $@ exited with code $ret_local"
     else
      echo "`date` Postscript $1 does NOT exist." | tee -a $logfile
      return_value=-1
     fi
     return 0
    }
    # subroutine end
    SHAREDTFTP='1'
    export SHAREDTFTP
    TFTPDIR='/tftpboot'
    export TFTPDIR
    CONSOLEONDEMAND='yes'
    export CONSOLEONDEMAND
    PPCTIMEOUT='300'
    export PPCTIMEOUT
    VSFTP='y'
    export VSFTP
    DOMAIN='cluster.com'
    export DOMAIN
    XCATIPORT='3002'
    export XCATIPORT
    DHCPINTERFACES="'xcatmn2|eth1;service|eth1'"
    export DHCPINTERFACES
    MAXSSH='10'
    export MAXSSH
    SITEMASTER=10.2.0.100
    export SITEMASTER
    TIMEZONE='America/New_York'
    export TIMEZONE
    INSTALLDIR='/install'
    export INSTALLDIR
    NTPSERVERS='xcatmn2'
    export NTPSERVERS
    EA_PRIMARY_HMC='c76v2hmc01'
    export EA_PRIMARY_HMC
    NAMESERVERS='10.2.0.100'
    export NAMESERVERS
    SNSYNCFILEDIR='/var/xcat/syncfiles'
    export SNSYNCFILEDIR
    DISJOINTDHCPS='0'
    export DISJOINTDHCPS
    FORWARDERS='8.112.8.1,8.112.8.2'
    export FORWARDERS
    VLANNETS='|(\d+)|10.10.($1+0).0|'
    export VLANNETS
    XCATDPORT='3001'
    export XCATDPORT
    USENMAPFROMMN='no'
    export USENMAPFROMMN
    DNSHANDLER='ddns'
    export DNSHANDLER
    ROUTENAMES='r1,r2'
    export ROUTENAMES
    INSTALLLOC='/install'
    export INSTALLLOC
    ENABLESSHBETWEENNODES=YES
    export ENABLESSHBETWEENNODES
    NETWORKS_LINES=4
     export NETWORKS_LINES
    NETWORKS_LINE1='netname=public_net||net=8.112.154.64||mask=255.255.255.192||mgtifname=eth0||gateway=8.112.154.126||dhcpserver=||tftpserver=8.112.154.69||nameservers=8.112.8.1||ntpservers=||logservers=||dynamicrange=||staticrange=||staticrangeincrement=||nodehostname=||ddnsdomain=||vlanid=||domain=||mtu=||disable=||comments='
    export NETWORKS_LINE2
    NETWORKS_LINE3='netname=sn21_net||net=10.2.1.0||mask=255.255.255.0||mgtifname=eth1||gateway=<xcatmaster>||dhcpserver=||tftpserver=||nameservers=10.2.1.100,10.2.1.101||ntpservers=||logservers=||dynamicrange=||staticrange=||staticrangeincrement=||nodehostname=||ddnsdomain=||vlanid=||domain=||mtu=||disable=||comments='
    export NETWORKS_LINE3
    NETWORKS_LINE4='netname=sn22_net||net=10.2.2.0||mask=255.255.255.0||mgtifname=eth1||gateway=10.2.2.100||dhcpserver=10.2.2.100||tftpserver=10.2.2.100||nameservers=10.2.2.100||ntpservers=||logservers=||dynamicrange=10.2.2.120-10.2.2.250||staticrange=||staticrangeincrement=||nodehostname=||ddnsdomain=||vlanid=||domain=||mtu=||disable=||comments='
    export NETWORKS_LINE4
    NODE=xcatsn23
    export NODE
    NFSSERVER=10.2.0.100
    export NFSSERVER
    INSTALLNIC=eth0
    export INSTALLNIC
    PRIMARYNIC=eth0
    export PRIMARYNIC
    MASTER=10.2.0.100
    export MASTER
    OSVER=sles11
    export OSVER
    ARCH=ppc64
    export ARCH
    PROFILE=service-xcattest
    export PROFILE
    PROVMETHOD=netboot
    export PROVMETHOD
    PATH=`dirname $0`:$PATH
    export PATH
    NODESETSTATE=netboot
    export NODESETSTATE
    UPDATENODE=1
    export UPDATENODE
    NTYPE=service
    export NTYPE
    MACADDRESS=16:3d:05:fa:4a:02
    export MACADDRESS
    NODEID=EA163d05fa4a02EA
    export NODEID
    MONSERVER=8.112.154.69
    export MONSERVER
    MONMASTER=10.2.0.100
    export MONMASTER
    MS_NODEID=0360238fe61815e6
    export MS_NODEID
    OSPKGS='kernel-ppc64,udev,sysconfig,aaa_base,klogd,device-mapper,bash,openssl,nfs- utils,ksh,syslog-ng,openssh,openssh-askpass,busybox,vim,rpm,bind,bind-utils,dhcp,dhcpcd,dhcp-server,dhcp-client,dhcp-relay,bzip2,cron,wget,vsftpd,util-linux,module-init-tools,mkinitrd,apache2,apache2-prefork,perl-Bootloader,psmisc,procps,dbus-1,hal,timezone,rsync,powerpc-utils,bc,iputils,uuid-runtime,unixODBC,gcc,zypper,tar'
    export OSPKGS
    OTHERPKGS1='xcat/xcat-core/xCAT-rmc,xcat/xcat-core/xCATsn,xcat/xcat-dep/sles11/ppc64/conserver,perl-DBD-mysql,nagios/nagios-nsca-client,nagios/nagios,nagios/nagios-plugins-nrpe,nagios/nagios-nrpe'
    export OTHERPKGS1
    OTHERPKGS_INDEX=1
    export OTHERPKGS_INDEX
    ## get the diskless networks information. There may be no information.
    NETMASK=255.255.255.0
    export NETMASK
    GATEWAY=10.2.0.100
    export GATEWAY
    # NIC related attributes for the node for confignics postscript
    NICIPS=""
    export NICIPS
    NICHOSTNAMESUFFIXES=""
    export NICHOSTNAMESUFFIXES
    NICTYPES=""
    export NICTYPES
    NICCUSTOMSCRIPTS=""
    export NICCUSTOMSCRIPTS
    NICNETWORKS=""
    export NICNETWORKS
    NICCOMMENTS=
    export NICCOMMENTS
    # postscripts-start-here
    # defaults-postscripts-start-here
    run_ps test1
    run_ps syslog
    run_ps remoteshell
    run_ps syncfiles
    run_ps confNagios
    run_ps configrmcnode
    # defaults-postscripts-end-here
    # node-postscripts-start-here
    run_ps servicenode
    run_ps configeth_new
    # node-postscripts-end-here
    run_ps setbootfromnet
    # postscripts-end-here
    # postbootscripts-start-here
    # defaults-postbootscripts-start-here
    run_ps otherpkgs
    # defaults-postbootscripts-end-here
    # node-postbootscripts-start-here
    run_ps test
    # The following line node-postbootscripts-end-here must not be deleted.
    # node-postbootscripts-end-here
    # postbootscripts-end-here
    exit $return_value


