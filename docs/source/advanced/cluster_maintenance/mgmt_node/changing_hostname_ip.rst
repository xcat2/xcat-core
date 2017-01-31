Changing the hostname/IP address
================================

Overview
--------

This document is intended to describe the steps that must be taken if you need
to change your Linux Management Node's hostname and/or IP address
after the cluster is installed and configured by xCAT. This documentation will
only cover the changes by xCAT and will not try to cover any other changes by
any other tools.

Backup your xCAT data
---------------------

Clean up the database by running ``tabprune`` command: ::

  tabprune -a auditlog
  tabprune -a eventlog

Now take a snapshot of the Management Node. This will also create a database
backup. You can use this data as reference if needed. ::

  xcatsnap -d

Stop xCAT
---------

You need to stop the xcat daemon and any other applications that are using the
xCAT database on the Management Node and the Service Nodes. To determine your
database, run ::

  lsxcatd -a | grep dbengine

To stop xCAT: ::

  service xcatd stop

Stop The Database
-----------------

For all databases except SQlite, you should stop the database.
For example ::

  service postgresql stop
  service mysqld stop

Change the Management Hostname
-------------------------------

* hostname command ::

    hostname <new_MN_name>

* Update the hostname configuration files:

  |  Add hostname in ``/etc/hostname``
  |  Add HOSTNAME attribute in ``/etc/sysconfig/network`` (only for [RHEL])

Update Database Files
---------------------

You need to update the new MN hostname or IP address in several database configuration files.

SQLite
^^^^^^

Nothing to do.

PostgreSQL
^^^^^^^^^^

- Edit ``/etc/xcat/cfgloc`` file... 

   Replace ``Pg:dbname=xcatdb;host=<old_MN_ip>|xcatadm|xcat20`` with ``Pg:dbname=xcatdb;host=<new_MN_ip>|xcatadm|xcat20``.

- Edit config database config file ``/var/lib/pgsql/data/pg_hba.conf``...

  Replace ``host    all          all        <old_MN_ip>/32      md5`` with ``host    all          all        <new_MN_ip>/32      md5``

MySQL
^^^^^

- Edit ``/etc/xcat/cfglooc``... 
    Replace ``mysql:dbname=xcatdb;host=<old_MN_ip>|xcatadmin|xcat20`` with ``mysql:dbname=xcatdb;host=<new_MN_ip>|xcatadmin|xcat20``

Start the database
------------------

::

   service postgresql start
   service mysqld start

Start xCAT

::

   service xcatd start

Verify your new database setup ::

  lsxcatd -a | grep dbengine
  tabdump site  # if output exists

Change The Definition In xCAT Database
--------------------------------------

Change the site table master attribute
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

::

  chdef -t site master=<new_MN_ip>

Change all IP address attribute relevant to the MN IP address
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

For example, the old IP address was "10.6.0.1"

* Query all the attributes with old address ::

    lsdef -t node -l | grep "10.6.0.1"
      ...
      conserver=10.6.0.1
      conserver=10.6.0.1
      conserver=10.6.0.1
      conserver=10.6.0.1
      nfsserver=10.6.0.1
      servicenode=10.6.0.1
      xcatmaster=10.6.0.1
      kcmdline=quiet repo=http://10.6.0.1/install/rhels6/ppc64/ ks=http://10.6.0.1/install/autoinst
      /slessn ksdevice=d6:92:39:bf:71:05
      nfsserver=10.6.0.1
      servicenode=10.6.0.1
      tftpserver=10.6.0.1
      xcatmaster=10.6.0.1
      servicenode=10.6.0.1
      xcatmaster=10.6.0.1

* Looking at the list above, taking ``conserver`` as an example, query the nodes with ``conserver=10.6.0.1``: ::

    lsdef -t node -w conserver="10.6.0.1"
      ...
      cn1  (node)
      cn2  (node)
      cn3  (node)
      cn4  (node)

* Change the conserver address for nodes ``cn1,cn2,cn3,cn4`` ::

    chdef -t node cn1-cn4 conserver=<new_ip_address>

* Repeat the same process for the other attributes containing the old IP address. 

Change networks table
^^^^^^^^^^^^^^^^^^^^^

Check your networks table to see if the network definitions are still correct,
if not edit accordingly ::

  lsdef -t network -l
  chdef -t network <key=value>

Check Result
^^^^^^^^^^^^

You can check whether all the old address has been changed using ::

  dumpxCATdb -P <new database backup path>
  cd <new database backup path>
  fgrep "10.6.0.1" *.csv

If the old address still exists in the ``*.csv`` file, you can edit this file, then use the following command to restore the records ::

  tabrestore <xxx.csv>

Generate SSL credentials(optional)
----------------------------------

Use the following command to generate new SSL credentials: ``xcatconfig -c``. 

Then update the following in xCAT:

* Update the policy table with new management node name and replace: ::

     "1.4","old_MN_name",,,,,,"trusted",,

  with: ::

     "1.4","new_MN_name",,,,,,"trusted",,``

* Setup up conserver with new credentials ::

    makeconservercf

External DNS Server Changed
---------------------------

* Update nameserver entries in ``/etc/resolv.conf``
* Update nameserver attribute in ``site`` table ::

    chdef -t site -o clustersite nameservers="new_ip_address1,new_ip_address2"

* Update site forwarders in DB ::

    chdef -t site -o clustersite forwarders="new_ip_address1,new_ip_address2"

* Run command ``makedns -n``

Domain Name Changed
-------------------

Change the entries in ``/etc/hosts``.

Change the ``/etc/resolv.conf``, forwarders attribute in site table. ::

  lsdef -t site -o clustersite -i forwarders
  chdef -t site -o clustersite forwarders <new list>

Change the domain name in the xCAT database site table. ::

  chdef -t site -o clustersite domain=<new_domainname>

From xCAT 2.8, multiple domains is supported in the cluster. Update the
networks table definition. ::

  lsdef -t network -l
  chdef -t network -o <network_name> ddnsdomain=<new_domainname1,new_domainname2>

Update the Provision Environment
--------------------------------

Determine if the Management node is defined in the database, assuming it was
done correctly using xcatconfig -m, by running: ::

  lsdef __mgmtnode

If it exists, then use the return name and do the following:

  - Remove the MN from DNS configuration ::

      makedns -d <old_MN_name>

  - Remove the MN from the DHCP configuration ::

      makedns -d <old_MN_name>

  - Remove the MN from the conserver configuration ::

      makedns -d <old_MN_name>

  - Change the MN name in the xCAT database ::

      chdef -t node -o <old_MN_name> -n <new_MN_name>

  - Add the new MN to DNS ::

      makedns -n

  - Add the MN to dhcp ::

      makedhcp -a

  - Add the MN to conserver ::

      makeconservercf

Update the genesis packages
---------------------------

Run ``mknb <arch>`` after changing the ip of MN.

