.. _setup_xcat_high_available_management_node_with_nfs:

Setup xCAT HA Mgmt with NFS pacemaker and corosync 
====================================================================================

In this doc, we will configure a xCAT HA cluster using ``pacemaker`` and ``corosync`` based on NFS server. ``pacemaker`` and ``corosync`` only support ``x86_64`` systems, more information about ``pacemaker`` and ``corosync`` refer to doc :ref:`setup_ha_mgmt_node_with_drbd_pacemaker_corosync`.

Prepare environments
--------------------

The NFS SERVER IP is: c902f02x44 10.2.2.44

The NFS shares are ``/disk1/install``, ``/etc/xcat``, ``/root/.xcat``, ``/root/.ssh/``, ``/disk1/hpcpeadmin``

First xCAT Management node is: rhmn1 10.2.2.235

Second xCAT Management node is: rhmn2 10.2.2.233

Virtual IP: 10.2.2.150

This example will use static IP to provision nodes, so we do not use dhcp service. If you want to use dhcp service, you should consider to save dhcp related configuration files in NFS server.
The DB is SQLlite. There is no service node in this example.

Prepare NFS server
--------------------

In NFS server 10.2.2.44, execute commands to export fs; If you want to use another non-root user to manage xCAT, such as hpcpeadmin. 
You should create a directory for ``/home/hpcpeadmin``; Execute commands in NFS server c902f02x44. ::

    # service nfs start
    # mkdir ~/.xcat 
    # mkdir -p /etc/xcat
    # mkdir -p /disk1/install/
    # mkdir -p /disk1/hpcpeadmin
    # mkdir -p /disk1/install/xcat

    # vi /etc/exports 
    /disk1/install *(rw,no_root_squash,sync,no_subtree_check) 
    /etc/xcat *(rw,no_root_squash,sync,no_subtree_check) 
    /root/.xcat *(rw,no_root_squash,sync,no_subtree_check)
    /root/.ssh *(rw,no_root_squash,sync,no_subtree_check)
    /disk1/hpcpeadmin *(rw,no_root_squash,sync,no_subtree_check)
    # exportfs -a

Install First xCAT MN rhmn1
------------------------------

Execute steps on xCAT MN rhmn1

#. Configure IP alias in rhmn1: ::

    ifconfig eth0:0 10.2.2.250 netmask 255.0.0.0

#. Add alias ip into ``/etc/resolv.conf``: ::

    #vi /etc/resolv.conf
    search pok.stglabs.ibm.com
    nameserver 10.2.2.250

   ``rsync`` /etc/resolv.conf to ``c902f02x44:/disk1/install/xcat/``: ::

    rsync /etc/resolv.conf c902f02x44:/disk1/install/xcat/

   Add alias ip，rhmn2,rhmn1 into ``/etc/hosts``: ::

    #vi /etc/hosts
    10.2.2.233  rhmn2 rhmn2.pok.stglabs.ibm.com
    10.2.2.235  rhmn1 rhmn1.pok.stglabs.ibm.com

   ``rsync`` /etc/hosts to ``c902f02x44:/disk1/install/xcat/``: ::

    rsync /etc/hosts c902f02x44:/disk1/install/xcat/

#. Install first xcat MN rhmn1

   Mount share nfs from 10.2.2.44: ::

    # mkdir -p /install 
    # mkdir -p /etc/xcat
    # mkdir -p /home/hpcpeadmin
    # mount 10.2.2.44:/disk1/install /install
    # mount 10.2.2.44:/etc/xcat /etc/xcat
    # mkdir -p /root/.xcat 
    # mount 10.2.2.44:/root/.xcat /root/.xcat
    # mount 10.2.2.44:/root/.ssh /root/.ssh
    # mount 10.2.2.44:/disk1/hpcpeadmin /home/hpcpeadmin

   Create new user hpcpeadmin, change it password to hpcpeadminpw: ::

    # USER="hpcpeadmin"
    # GROUP="hpcpeadmin"
    # /usr/sbin/groupadd -f ${GROUP}
    # /usr/sbin/useradd ${USER} -d /home/${USER} -s /bin/bash
    # /usr/sbin/usermod -a -G ${GROUP} ${USER}
    # passwd ${USER}

   Change new user hpcpeadmin as sudoers: ::

    # USERNAME="hpcpeadmin"
    # SUDOERS_FILE="/etc/sudoers"
    # sed s'/Defaults    requiretty/#Defaults    requiretty'/g ${SUDOERS_FILE} > /tmp/sudoers
    # echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /tmp/sudoers
    # cp -f /tmp/sudoers ${SUDOERS_FILE}
    # chown hpcpeadmin:hpcpeadmin /home/hpcpeadmin
    # rm -rf /tmp/sudoers

   Check the result: ::

    #su - hpcpeadmin
    $ sudo cat /etc/sudoers|grep hpcpeadmin
    hpcpeadmin ALL=(ALL) NOPASSWD:ALL
     $exit

   Download xcat-core tar ball and xcat-dep tar ball from github, and untar them: ::

    # mkdir /install/xcat 
    # mv xcat-core-2.8.4.tar.bz2 /install/xcat/ 
    # mv xcat-dep-201404250449.tar.bz2 /install/xcat/
    # cd /install/xcat 
    # tar -jxvf xcat-core-2.8.4.tar.bz2
    # tar -jxvf xcat-dep-201404250449.tar.bz2
    # cd xcat-core
    # ./mklocalrepo.sh
    # cd ../xcat-dep/rh6/x86_64/
    # ./mklocalrepo.sh 
    # yum clean metadata
    # yum install xCAT
    # source /etc/profile.d/xcat.sh

#. Use vip in site table and networks table: ::

    # chdef -t site master=10.2.2.250 nameservers=10.2.2.250
    # chdef -t network 10_0_0_0-255_0_0_0 tftpserver=10.2.2.250
    # tabdump networks
    ~]#netname,net,mask,mgtifname,gateway,dhcpserver,tftpserver,nameservers,ntpservers,logservers,dynamicrange,staticrange,staticrangeincrement,nodehostname,ddnsdomain,vlanid,domain,mtu,comments,disable
    "10_0_0_0-255_0_0_0","10.0.0.0","255.0.0.0","eth0","10.2.0.221",,"10.2.2.250",,,,,,,,,,,,,

#. Add 2 nodes into policy table: ::

    #tabedit policy
    "1.2","rhmn1",,,,,,"trusted",,
    "1.3","rhmn2",,,,,,"trusted",,

#. Backup xcatDB(optional): ::

    dumpxCATdb -p <yourbackupdir>.

#. Check and handle the policy table to allow the user to run commands: ::

    # chtab policy.priority=6 policy.name=hpcpeadmin policy.rule=allow
    # tabdump policy
    /#priority,name,host,commands,noderange,parameters,time,rule,comments,disable
    "1","root",,,,,,"allow",,
    "1.2","rhmn1",,,,,,"trusted",,
    "1.3","rhmn2",,,,,,"trusted",,
    "2",,,"getbmcconfig",,,,"allow",,
    "2.1",,,"remoteimmsetup",,,,"allow",,
    "2.3",,,"lsxcatd",,,,"allow",,
    "3",,,"nextdestiny",,,,"allow",,
    "4",,,"getdestiny",,,,"allow",,
    "4.4",,,"getpostscript",,,,"allow",,
    "4.5",,,"getcredentials",,,,"allow",,
    "4.6",,,"syncfiles",,,,"allow",,
    "4.7",,,"litefile",,,,"allow",,
    "4.8",,,"litetree",,,,"allow",,
    "6","hpcpeadmin",,,,,,"allow",,

#. Make sure xCAT commands are in the users path ::

    # su - hpcpeadmin
    $ echo $PATH | grep xcat
     /opt/xcat/bin:/opt/xcat/sbin:/opt/xcat/share/xcat/tools:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin:/home/hpcpeadmin/bin
    $lsdef -t site -l

#. Stop the xcatd daemon and some related network services from starting on reboot ::

    # service xcatd stop
    Stopping xCATd [ OK ]
    # chkconfig --level 345 xcatd off
    # service conserver stop
    conserver not running, not stopping [PASSED]
    # chkconfig --level 2345 conserver off
    # service dhcpd stop
    # chkconfig --level 2345 dhcpd off

   Remove the Virtual Alias IP ::

    # ifconfig eth0:0 0.0.0.0 0.0.0.0

Install second xCAT MN node rhmn2
-------------------------------------

The installation steps are the exactly same with above part ``Install fist xCAT MN node rhmn1``, using the same VIP with rhmn1.

SSH Setup Across nodes rhmn1 and rhmn2
---------------------------------------------

Setup ssh across nodes rhmn1 and rhmn2, make sure rhmn1 can ssh to rhmn2 using no password: ::

    cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
    rsync -ave ssh /etc/ssh/ rhmn2:/etc/ssh/
    rsync -ave ssh /root/.ssh/ rhmn2:/root/.ssh/

``Note``: if they can ssh each other using password, it is enough.

Install corosync and pacemaker on both rhmn2 and rhmn1
-------------------------------------------------------------

#. Download crmsh pssh python-pssh: ::

    wget download.opensuse.org/repositories/network:/ha-clustering:/Stable/RedHat_RHEL-6/x86_64/crmsh-2.1-1.1.x86_64.rpm
    wget download.opensuse.org/repositories/network:/ha-clustering:/Stable/RedHat_RHEL-6/x86_64/pssh-2.3.1-4.2.x86_64.rpm
    wget download.opensuse.org/repositories/network:/ha-clustering:/Stable/RedHat_RHEL-6/x86_64/python-pssh-2.3.1-4.2.x86_64.rpm
    rpm -ivh python-pssh-2.3.1-4.2.x86_64.rpm
    rpm -ivh pssh-2.3.1-4.2.x86_64.rpm
    yum install redhat-rpm-config
    rpm -ivh crmsh-2.1-1.1.x86_64.rpm

#. Install ``corosync`` and ``pacemaker`` from OS repositories: ::

    #cd /etc/yum.repos.d
    #cat rhel-local.repo
    [rhel-local]
    name=HPCCloud configured local yum repository for rhels6.5/x86_64
    baseurl=http://10.2.0.221/install/rhels6.5/x86_64
    enabled=1
    gpgcheck=0

    [rhel-local1]
    name=HPCCloud1 configured local yum repository for rhels6.5/x86_64
    baseurl=http://10.2.0.221/install/rhels6.5/x86_64/HighAvailability
    enabled=1
    gpgcheck=0

#. Install ``corosync`` and ``pacemaker``, then generate ssh key: 

   Install ``corosync`` and ``pacemaker``: ::

    yum install -y corosync pacemaker

   Generate a Security Key, first generate a security key for authentication for all nodes in the cluster,
   On one of the systems in the corosync cluster enter: ::

    corosync-keygen

   It will look like the command is not doing anything. It is waiting for entropy data
   to be written to ``/dev/random`` until it gets 1024 bits. You can speed that process
   up by going to another console for the system and entering: ::

    cd /tmp
    wget http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.32.8.tar.bz2
    tar xvfj linux-2.6.32.8.tar.bz2
    find .

   This should create enough i/o, needed for entropy.
   Then you need to copy that file to all of your nodes and put it in /etc/corosync/
   with ``user=root``, ``group=root`` and mode 0400: ::

    chmod 400 /etc/corosync/authkey
    scp /etc/corosync/authkey vm2:/etc/corosync/

#. Edit corosync.conf: ::

    #cat /etc/corosync/corosync.conf
    #Please read the corosync.conf.5 manual page
     compatibility: whitetank
     totem {
        version: 2
        secauth: off
        threads: 0
        interface {
                member {
                      memberaddr: 10.2.2.233
                       }
                member {
                      memberaddr: 10.2.2.235
                       }
                ringnumber: 0
                bindnetaddr: 10.2.2.0
                mcastport: 5405
        }
        transport: udpu
     }
     logging {
        fileline: off
        to_stderr: no
        to_logfile: yes
        to_syslog: yes
        logfile: /var/log/cluster/corosync.log
        debug: off
        timestamp: on
        logger_subsys {
                subsys: AMF
                debug: off
        }
     }
     amf {
        mode: disabled
     }

#. Configure ``pacemaker``: ::

    #vi /etc/corosync/service.d/pcmk
    service {
    name: pacemaker
    ver: 1
    }

#. Synchronize: ::

    for f in /etc/corosync/corosync.conf /etc/corosync/service.d/pcmk; do scp $f rhmn2:$f; done

#. Start ``corosync`` and ``pacemaker`` in both rhmn1 and rhmn2: ::

    # /etc/init.d/corosync start
    Starting Corosync Cluster Engine (corosync): [ OK ]
    # /etc/init.d/pacemaker start
    Starting Pacemaker Cluster Manager[ OK ]

#. Verify and let stonith false: ::

    # crm_verify -L -V
    error: unpack_resources: Resource start-up disabled since no STONITH resources have been defined
    error: unpack_resources: Either configure some or disable STONITH with the stonith-enabled option
    error: unpack_resources: NOTE: Clusters with shared data need STONITH to ensure data integrity
    Errors found during check: config not valid
    # crm configure property stonith-enabled=false

Customize corosync/pacemaker configuration for xCAT
------------------------------------------------------

Be aware that you need to apply ALL the configuration at once. You cannot pick and choose which pieces to put in, and you cannot put some in now, and some later. Don't execute individual commands, but use crm configure edit instead.

    Check that both rhmn2 and chetha are standby state now: ::

     rhmn1 ~]# crm status 
     Last updated: Wed Aug 13 22:57:58 2014 
     Last change: Wed Aug 13 22:40:31 2014 via cibadmin on rhmn1 
     Stack: classic openais (with plugin) 
     Current DC: rhmn2 - partition with quorum 
     Version: 1.1.8-7.el6-394e906 
     2 Nodes configured, 2 expected votes 
     14 Resources configured. 
     Node rhmn1: standby 
     Node rhmn2: standby

    Execute ``crm configure edit`` to add all configure at once: ::

     rhmn1 ~]# crm configure edit
     node rhmn1
     node rhmn2 \
             attributes standby=on
     primitive ETCXCATFS Filesystem \
             params device="10.2.2.44:/etc/xcat" fstype=nfs options=v3 directory="/etc/xcat" \
             op monitor interval=20 timeout=40
     primitive HPCADMIN Filesystem \
             params device="10.2.2.44:/disk1/hpcpeadmin" fstype=nfs options=v3     directory="/home/hpcpeadmin" \
             op monitor interval=20 timeout=40
     primitive ROOTSSHFS Filesystem \
             params device="10.2.2.44:/root/.ssh" fstype=nfs options=v3 directory="/root/.ssh" \
             op monitor interval=20 timeout=40
     primitive INSTALLFS Filesystem \
             params device="10.2.2.44:/disk1/install" fstype=nfs options=v3 directory="/install" \
             op monitor interval=20 timeout=40
     primitive NFS_xCAT lsb:nfs \
             op start interval=0 timeout=120s \
             op stop interval=0 timeout=120s \
             op monitor interval=41s
     primitive NFSlock_xCAT lsb:nfslock \
             op start interval=0 timeout=120s \
             op stop interval=0 timeout=120s \
             op monitor interval=43s
     primitive ROOTXCATFS Filesystem \
             params device="10.2.2.44:/root/.xcat" fstype=nfs options=v3 directory="/root/.xcat" \
             op monitor interval=20 timeout=40
     primitive apache_xCAT apache \
             op start interval=0 timeout=600s \
             op stop interval=0 timeout=120s \
             op monitor interval=57s timeout=120s \
             params configfile="/etc/httpd/conf/httpd.conf" statusurl="http://localhost:80/icons/README.html" testregex="</html>" \
             meta target-role=Started
     primitive dummy Dummy \
             op start interval=0 timeout=600s \
             op stop interval=0 timeout=120s \
             op monitor interval=57s timeout=120s \
             meta target-role=Started
     primitive named lsb:named \
             op start interval=0 timeout=120s \
             op stop interval=0 timeout=120s \
             op monitor interval=37s
     primitive dhcpd lsb:dhcpd \
             op start interval="0" timeout="120s" \
             op stop interval="0" timeout="120s" \
             op monitor interval="37s"
     primitive xCAT lsb:xcatd \
             op start interval=0 timeout=120s \
             op stop interval=0 timeout=120s \
             op monitor interval=42s \
             meta target-role=Started
     primitive xCAT_conserver lsb:conserver \
             op start interval=0 timeout=120s \
             op stop interval=0 timeout=120s \
             op monitor interval=53
     primitive xCATmnVIP IPaddr2 \
             params ip=10.2.2.250 cidr_netmask=8 \
             op monitor interval=30s
     group XCAT_GROUP INSTALLFS ETCXCATFS ROOTXCATFS HPCADMIN ROOTSSHFS \
             meta resource-stickiness=100 failure-timeout=60 migration-threshold=3 target-role=Started
     clone clone_named named \
             meta clone-max=2 clone-node-max=1 notify=false
     colocation colo1 inf: NFS_xCAT XCAT_GROUP
     colocation colo2 inf: NFSlock_xCAT XCAT_GROUP
     colocation colo4 inf: apache_xCAT XCAT_GROUP
     colocation colo7 inf: xCAT_conserver XCAT_GROUP
     colocation dummy_colocation inf: dummy xCAT
     colocation xCAT_colocation inf: xCAT XCAT_GROUP
     colocation xCAT_makedns_colocation inf: xCAT xCAT_makedns
     order Most_aftergrp inf: XCAT_GROUP ( NFS_xCAT NFSlock_xCAT apache_xCAT xCAT_conserver )
     order Most_afterip inf: xCATmnVIP ( apache_xCAT xCAT_conserver )
     order clone_named_after_ip_xCAT inf: xCATmnVIP clone_named
     order dummy_order0 inf: NFS_xCAT dummy
     order dummy_order1 inf: xCAT dummy
     order dummy_order2 inf: NFSlock_xCAT dummy
     order dummy_order3 inf: clone_named dummy
     order dummy_order4 inf: apache_xCAT dummy
     order dummy_order7 inf: xCAT_conserver dummy
     order dummy_order8 inf: xCAT_makedns dummy
     order xcat_makedns inf: xCAT xCAT_makedns
     order dummy_order5 inf: dhcpd dummy
     property cib-bootstrap-options: \
             dc-version=1.1.8-7.el6-394e906 \
             cluster-infrastructure="classic openais (with plugin)" \
             expected-quorum-votes=2 \
             stonith-enabled=false \
             last-lrm-refresh=1406859140
     \#vim:set syntax=pcmk

Verify auto fail over
-------------------------

#. Online rhmn1

   Currently, rhmn2 and rhmn1 status are standby, let us online rhmn1: ::

     rhmn2 ~]# crm node online rhmn1
     rhmn2 /]# crm status
     Last updated: Mon Aug  4 23:16:44 2014
     Last change: Mon Aug  4 23:13:09 2014 via crmd on rhmn2
     Stack: classic openais (with plugin)
     Current DC: rhmn1 - partition with quorum
     Version: 1.1.8-7.el6-394e906
     2 Nodes configured, 2 expected votes
     12 Resources configured.
     Node rhmn2: standby
     Online: [ rhmn1 ]
     Resource Group: XCAT_GROUP
          xCATmnVIP  (ocf::heartbeat:IPaddr2):       Started rhmn1
          INSTALLFS  (ocf::heartbeat:Filesystem):    Started rhmn1
          ETCXCATFS  (ocf::heartbeat:Filesystem):    Started rhmn1
          ROOTXCATFS (ocf::heartbeat:Filesystem):    Started rhmn1
     NFS_xCAT       (lsb:nfs):      Started rhmn1
     NFSlock_xCAT   (lsb:nfslock):  Started rhmn1
     apache_xCAT    (ocf::heartbeat:apache):        Started rhmn1
     xCAT   (lsb:xcatd):    Started rhmn1
     xCAT_conserver (lsb:conserver):        Started rhmn1
     dummy  (ocf::heartbeat:Dummy): Started rhmn1
      Clone Set: clone_named [named]
          Started: [ rhmn1 ]
          Stopped: [ named:1 ]

#. xcat on rhmn2 is not working while it is running in rhmn1: ::

     rhmn2 /]# lsdef -t site -l
     Unable to open socket connection to xcatd daemon on localhost:3001.
     Verify that the xcatd daemon is running and that your SSL setup is correct.
     Connection failure: IO::Socket::INET: connect: Connection refused at /opt/xcat/lib/perl/xCAT/Client.pm line 217.

     rhmn2 /]# ssh rhmn1 "lsxcatd -v"
     Version 2.8.4 (git commit 7306ca8abf1c6d8c68d3fc3addc901c1bcb6b7b3, built Mon Apr 21 20:48:59 EDT 2014)

#. Let rhmn1 standby and rhmn2 online, xcat will run on rhmn2: ::

     rhmn2 /]# crm node online rhmn2
     rhmn2 /]# crm node standby rhmn1 
     rhmn2 /]# crm status 
     Last updated: Mon Aug 4 23:19:33 2014 
     Last change: Mon Aug 4 23:19:40 2014 via crm_attribute on rhmn2 
     Stack: classic openais (with plugin) 
     Current DC: rhmn1 - partition with quorum 
     Version: 1.1.8-7.el6-394e906 
     2 Nodes configured, 2 expected votes 
     12 Resources configured. 

     Node rhmn1: standby 
     Online: [ rhmn2 ] 

     Resource Group: XCAT_GROUP 
     xCATmnVIP (ocf::heartbeat:IPaddr2): Started rhmn2 
     INSTALLFS (ocf::heartbeat:Filesystem): Started rhmn2 
     ETCXCATFS (ocf::heartbeat:Filesystem): Started rhmn2 
     ROOTXCATFS (ocf::heartbeat:Filesystem): Started rhmn2 
     NFSlock_xCAT (lsb:nfslock): Started rhmn2 
     xCAT (lsb:xcatd): Started rhmn2 
     Clone Set: clone_named [named] 
     Started: [ rhmn2 ] 
     Stopped: [ named:1 ] 

     rhmn2 /]#lsxcatd -v
     Version 2.8.4 (git commit 7306ca8abf1c6d8c68d3fc3addc901c1bcb6b7b3, built Mon Apr 21 20:48:59 EDT 2014)


