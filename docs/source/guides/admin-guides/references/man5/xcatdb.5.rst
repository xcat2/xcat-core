
########
xcatdb.5
########

.. highlight:: perl


****
NAME
****


An overview of the xCAT database.


***********
DESCRIPTION
***********


The xCAT database contains user settings for the cluster and information gathered from the cluster.
It consists of a series of tables, which are described below.  To get more information about a
particular table, run man for that table name.  The tables can be manipulated directly using the
\ **tabedit**\  or \ **chtab**\  commands.  They can be viewed using \ **nodels**\  or \ **tabdump**\ .

Alternatively, the xCAT database can be viewed and edited as logical objects, instead of flat tables.
In this mode, xCAT takes care of which table each attribute should go in.  To treat the database
as logical object definitions, use the commands:  \ **lsdef**\ , \ **mkdef**\ , \ **chdef**\ , \ **rmdef**\ .  See Object Definitions
below.

xCAT allows the use of different database applications, depending on the needs of your cluster.
The default database is SQLite, which is a daemonless, zero-config database.  But you could instead
choose to use something like postgresql for greater scalability and remote access in the
hierarchical/service node case.  To use a different database or a different location, create
the file /etc/xcat/cfgloc.  See the appropriate xCAT docuementation for the format of the file for the database you choose. 
The following example /etc/xcat/cfgloc file is for PostgreSQL:


.. code-block:: perl

  Pg:dbname=xcat;host=<mgmtnode>|<pgadminuserid>|<pgadminpasswd>


where mgmtnode is the hostname of the management node adapter on the cluster side, and the pgadminuserid and pgadminpasswd are the database admin and password.

GROUPS AND REGULAR EXPRESSIONS IN TABLES
========================================


The xCAT database has a number of tables, some with rows that are keyed by node name
(such as noderes and nodehm) and others that are not keyed by node name (for example, the policy table).
The tables that are keyed by node name have some extra features that enable a more
template-based style to be used:

Any group name can be used in lieu of a node name in the node field, and that row will then
provide "default" attribute values for any node in that group.  A row with a specific node name
can then override one or more attribute values for that specific node.  For example, if the nodehm table contains:


.. code-block:: perl

  #node,power,mgt,cons,termserver,termport,conserver,serialport,serialspeed,serialflow,getmac,cmdmapping,comments,disable
  "mygroup",,"ipmi",,,,,,"19200",,,,,
  "node1",,,,,,,,"115200",,,,,


In the above example, the node group called mygroup sets mgt=ipmi and serialspeed=19200.  Any nodes that are in this group
will have those attribute values, unless overridden.  For example, if node2 is a member of mygroup, it will automatically
inherit these attribute values (even though it is not explicitly listed in this table).  In the case of node1 above, it
inherits mgt=ipmi, but overrides the serialspeed to be 115200, instead of 19200.  A useful, typical way to use this
capability is to create a node group for your nodes and for all the attribute values that are the same for every node,
set them at the group level.  Then you only have to set attributes for each node that vary from node to node.

xCAT extends the group capability so that it can also be used for attribute values that vary from node to node
in a very regular pattern.  For example, if in the ipmi table you want the bmc attribute to be set to whatever the nodename is with
"-bmc" appended to the end of it, then use this in the ipmi table:


.. code-block:: perl

  #node,bmc,bmcport,taggedvlan,bmcid,username,password,comments,disable
  "compute","/\z/-bmc/",,,,,,,


In this example, "compute" is a node group that contains all of the compute nodes.  The 2nd attribute (bmc) is a regular
expression that is similar to a substitution pattern.  The 1st part "\z" matches the end of the node name and substitutes "-bmc", effectively appending it to the node name.

Another example is if node1 is to have IP address 10.0.0.1, node2 is to have IP address 10.0.0.2, etc.,
then this could be represented in the hosts table with the single row:


.. code-block:: perl

  #node,ip,hostnames,otherinterfaces,comments,disable
  "compute","|node(\d+)|10.0.0.($1+0)|",,,,


In this example, the regular expression in the ip attribute uses "|" to separate the 1st and 2nd part.  This means that
xCAT will allow arithmetic operations in the 2nd part.  In the 1st part, "(\d+)", will match the number part of the node
name and put that in a variable called $1.  The 2nd part
is what value to give the ip attribute.  In this case it will set it to the string "10.0.0." and the number that is
in $1.  (Zero is added to $1 just to remove any leading zeroes.)

A more involved example is with the mp table.  If your blades have node names node01, node02, etc., and your chassis
node names are cmm01, cmm02, etc., then you might have an mp table like:


.. code-block:: perl

  #node,mpa,id,nodetype,comments,disable
  "blade","|\D+(\d+)|cmm(sprintf('%02d',($1-1)/14+1))|","|\D+(\d+)|(($1-1)%14+1)|",,


Before you panic, let me explain each column:


\ **blade**\ 
 
 This is a group name.  In this example, we are assuming that all of your blades belong to this
 group.  Each time the xCAT software accesses the \ **mp**\  table to get the management module and slot number
 of a specific blade (e.g. \ **node20**\ ), this row will match (because \ **node20**\  is in the \ **blade**\  group).
 Once this row is matched for \ **node20**\ , then the processing described in the following items will take
 place.
 


\ **|\D+(\d+)|cmm(sprintf('%02d',($1-1)/14+1))|**\ 
 
 This is a perl substitution pattern that will produce the value for the second column of the table (the
 management module hostname).  The text \ **\D+(\d+)**\  between the 1st two vertical bars is
 a regular expression that matches the node
 name that was searched for in this table (in this example \ **node20**\ ).  The text that matches
 within the 1st set of parentheses is set to $1.  (If there was a 2nd set of parentheses, it would
 be set to $2, and so on.)  In our case, the \D+ matches the non-numeric part of the name
 (\ **node**\ ) and the \ **\d+**\  matches the numeric part (\ **20**\ ).  So $1 is set to \ **20**\ .  The text \ **cmm(sprintf('%02d',($1-1)/14+1))**\  between the
 2nd and 3rd vertical bars produces the string that should be used as the value for the mpa attribute for node20.
 Since $1 is set to 20, the expression \ **($1-1)/14+1**\  equals
 19/14 + 1, which equals 2.  (The division is integer division,
 so 19/14 equals 1.  Fourteen is used as the divisor, because there are 14 blades in each chassis.)  The value of 2 is then passed into sprintf() with a format string to add a leading
 zero, if necessary, to always make the number two digits.  Lastly the string \ **cmm**\  is added to the beginning,
 making the resulting string \ **cmm02**\ , which will be used as the hostname
 of the management module.
 


\ **|\D+(\d+)|(($1-1)%14+1)|**\ 
 
 This item is similar to the one above.  This substituion pattern will produce the value for
 the 3rd column (the chassis slot number for this blade).  Because this row was
 the match for \ **node20**\ , the parentheses
 within the 1st set of vertical bars will set $1 to 20.  Since % means modulo division, the
 expression \ **($1-1)%14+1**\  will evaluate to \ **6**\ .
 


See http://www.perl.com/doc/manual/html/pod/perlre.html for information on perl regular expressions.


Regular Expression Helper Functions
============================

xCAT provides several functions that can simplify regular expressions.

\ **a2idx(character) **\
 Turns a single character into a 1-indexed index. ‘a’ maps to 1 and ‘z’ maps to 26.

\ **a2zidx(character) **\
 Turns a single character into a 0-indexed index. ‘a’ maps to 0 and ‘z’ maps to 25.

\ **dim2idx(value, [count, value...]) **\
 Converts dimensions (such as row, column, chassis, etc) into an index.  If each rack has 18 nodes, use dim2idx(racknum, 18, nodenum). Additional dimensions should be added at the beginning. All values are 1-indexed.

\ **skip(index, skiplist) **\
 Return an index with certain values skipped.  The skip list uses the format start[:count][,start[:count]...]

\ **ipadd(octet1, octet2, octet3, octet4, toadd, skipstart, skipend) **\
 Add to an IP address. Generally only necessary when you cross octets. Optionally skip addresses at the start and end of octets (like .0 or .255). Technically those are valid IP addresses, but sometimes software makes poor assumptions about which broadcast and gateway addresses. 


Easy Regular Expressions
========================


As of xCAT 2.8.1, you can use a modified version of the regular expression support described in the previous section. You do not need to enter the node information (1st part of the expression), it will be derived from the input nodename. You only need to supply the 2nd part of the expression to determine the value to give the attribute. For examples, see

http://xcat-docs.readthedocs.org/en/latest/guides/admin-guides/basic_concepts/xcat_db/regexp_db.html#easy-regular-expressions



******************
OBJECT DEFINITIONS
******************


Because it can get confusing what attributes need to go in what tables, the xCAT database can also
be viewed and edited as logical objects, instead of flat tables.  Use \ **mkdef**\ , \ **chdef**\ , \ **lsdef**\ ,
and \ **rmdef**\  to create, change, list, and delete objects.
When using these commands, the object attributes will be stored in the same tables, as if you edited
the tables by hand.  The only difference is that the object commands take care of knowing which tables
all of the information should go in.

\ **xCAT Object Name Format**\ :
================================


\ **xCAT Object Name Format**\  is defined by the following regex:


.. code-block:: perl

  ^([A-Za-z-]+)([0-9]+)(([A-Za-z-]+[A-Za-z0-9-]*)*)


In plain English, an object name is in \ **xCAT Object Name Format**\  if starting from the begining there are:


\*
 
 one or more alpha characters of any case and any number of "-" in any combination
 


\*
 
 followed by one or more numbers
 


\*
 
 then optionally followed by one alpha character of any case  or "-"
 


\*
 
 followed by any combination of case mixed alphanumerics and "-"
 



\ **Object Types**\ 
====================


To run man for any of the object definitions below, use section 7.  For example:  \ **man 7 node**\ 

The object types are:


auditlog(7)|auditlog.7



boottarget(7)|boottarget.7



eventlog(7)|eventlog.7



firmware(7)|firmware.7



group(7)|group.7



kit(7)|kit.7



kitcomponent(7)|kitcomponent.7



kitrepo(7)|kitrepo.7



monitoring(7)|monitoring.7



network(7)|network.7



node(7)|node.7



notification(7)|notification.7



osdistro(7)|osdistro.7



osdistroupdate(7)|osdistroupdate.7



osimage(7)|osimage.7



pdu(7)|pdu.7



policy(7)|policy.7



rack(7)|rack.7



route(7)|route.7



site(7)|site.7



taskstate(7)|taskstate.7



zone(7)|zone.7





******
TABLES
******


To manipulate the tables directly, use \ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ ,
\ **nodeadd(8)**\ , \ **nodech(1)**\ .

To run man for any of the table descriptions below, use section 5.  For example:  \ **man 5 nodehm**\ 

The tables are:


auditlog(5)|auditlog.5
 
 Audit Data log.
 


bootparams(5)|bootparams.5
 
 Current boot settings to be sent to systems attempting network boot for deployment, stateless, or other reasons.  Mostly automatically manipulated by xCAT.
 


boottarget(5)|boottarget.5
 
 Specify non-standard initrd, kernel, and parameters that should be used for a given profile.
 


cfgmgt(5)|cfgmgt.5
 
 Configuration management data for nodes used by non-xCAT osimage management services to install and configure software on a node.
 


chain(5)|chain.5
 
 Controls what operations are done (and it what order) when a node is discovered and deployed.
 


deps(5)|deps.5
 
 Describes dependencies some nodes have on others.  This can be used, e.g., by rpower -d to power nodes on or off in the correct order.
 


discoverydata(5)|discoverydata.5
 
 Discovery data which sent from genesis.
 


domain(5)|domain.5
 
 Mapping of nodes to domain attributes
 


eventlog(5)|eventlog.5
 
 Stores the events occurred.
 


firmware(5)|firmware.5
 
 Maps node to firmware values to be used for setup at node discovery or later
 


hosts(5)|hosts.5
 
 IP addresses and hostnames of nodes.  This info is optional and is only used to populate /etc/hosts and DNS via makehosts and makedns.  Using regular expressions in this table can be a quick way to populate /etc/hosts.
 


hwinv(5)|hwinv.5
 
 The hareware inventory for the node.
 


hypervisor(5)|hypervisor.5
 
 Hypervisor parameters
 


ipmi(5)|ipmi.5
 
 Settings for nodes that are controlled by an on-board BMC via IPMI.
 


iscsi(5)|iscsi.5
 
 Contains settings that control how to boot a node from an iSCSI target
 


kit(5)|kit.5
 
 This table stores all kits added to the xCAT cluster.
 


kitcomponent(5)|kitcomponent.5
 
 This table stores all kit components added to the xCAT cluster.
 


kitrepo(5)|kitrepo.5
 
 This table stores all kits added to the xCAT cluster.
 


kvm_masterdata(5)|kvm_masterdata.5
 
 Persistent store for KVM plugin for masters
 


kvm_nodedata(5)|kvm_nodedata.5
 
 Persistent store for KVM plugin, not intended for manual modification.
 


linuximage(5)|linuximage.5
 
 Information about a Linux operating system image that can be used to deploy cluster nodes.
 


litefile(5)|litefile.5
 
 The litefile table specifies the directories and files on the statelite nodes that should be readwrite, persistent, or readonly overlay.  All other files in the statelite nodes come from the readonly statelite image.
 


litetree(5)|litetree.5
 
 Directory hierarchy to traverse to get the initial contents of node files.  The files that are specified in the litefile table are searched for in the directories specified in this table.
 


mac(5)|mac.5
 
 The MAC address of the node's install adapter.  Normally this table is populated by getmacs or node discovery, but you can also add entries to it manually.
 


mic(5)|mic.5
 
 The host, slot id and configuration of the mic (Many Integrated Core).
 


monitoring(5)|monitoring.5
 
 Controls what external monitoring tools xCAT sets up and uses.  Entries should be added and removed from this table using the provided xCAT commands monstart and monstop.
 


monsetting(5)|monsetting.5
 
 Specifies the monitoring plug-in specific settings. These settings will be used by the monitoring plug-in to customize the behavior such as event filter, sample interval, responses etc. Entries should be added, removed or modified by chtab command. Entries can also be added or modified by the monstart command when a monitoring plug-in is brought up.
 


mp(5)|mp.5
 
 Contains the hardware control info specific to blades.  This table also refers to the mpa table, which contains info about each Management Module.
 


mpa(5)|mpa.5
 
 Contains info about each Management Module and how to access it.
 


networks(5)|networks.5
 
 Describes the networks in the cluster and info necessary to set up nodes on that network.
 


nics(5)|nics.5
 
 Stores NIC details.
 


nimimage(5)|nimimage.5
 
 All the info that specifies a particular AIX operating system image that can be used to deploy AIX nodes.
 


nodegroup(5)|nodegroup.5
 
 Contains group definitions, whose membership is dynamic depending on characteristics of the node.
 


nodehm(5)|nodehm.5
 
 Settings that control how each node's hardware is managed.  Typically, an additional table that is specific to the hardware type of the node contains additional info.  E.g. the ipmi, mp, and ppc tables.
 


nodelist(5)|nodelist.5
 
 The list of all the nodes in the cluster, including each node's current status and what groups it is in.
 


nodepos(5)|nodepos.5
 
 Contains info about the physical location of each node.  Currently, this info is not used by xCAT, and therefore can be in whatevery format you want.  It will likely be used in xCAT in the future.
 


noderes(5)|noderes.5
 
 Resources and settings to use when installing nodes.
 


nodetype(5)|nodetype.5
 
 A few hardware and software characteristics of the nodes.
 


notification(5)|notification.5
 
 Contains registrations to be notified when a table in the xCAT database changes.  Users can add entries to have additional software notified of changes.  Add and remove entries using the provided xCAT commands regnotif and unregnotif.
 


openbmc(5)|openbmc.5
 
 Setting for nodes that are controlled by an on-board OpenBMC.
 


osdistro(5)|osdistro.5
 
 Information about all the OS distros in the xCAT cluster
 


osdistroupdate(5)|osdistroupdate.5
 
 Information about the OS distro updates in the xCAT cluster
 


osimage(5)|osimage.5
 
 Basic information about an operating system image that can be used to deploy cluster nodes.
 


passwd(5)|passwd.5
 
 Contains default userids and passwords for xCAT to access cluster components.  In most cases, xCAT will also actually set the userid/password in the relevant component when it is being configured or installed.  Userids/passwords for specific cluster components can be overidden in other tables, e.g. mpa, ipmi, ppchcp, etc.
 


pdu(5)|pdu.5
 
 Parameters to use when interrogating pdus
 


pduoutlet(5)|pduoutlet.5
 
 Contains list of outlet numbers on the pdu each node is connected to.
 


performance(5)|performance.5
 
 Describes the system performance every interval unit of time.
 


policy(5)|policy.5
 
 The policy table in the xCAT database controls who has authority to run specific xCAT operations. It is basically the Access Control List (ACL) for xCAT. It is sorted on the priority field before evaluating.
 


postscripts(5)|postscripts.5
 
 The scripts that should be run on each node after installation or diskless boot.
 


ppc(5)|ppc.5
 
 List of system p hardware: HMCs, IVMs, FSPs, BPCs, CECs, Frames.
 


ppcdirect(5)|ppcdirect.5
 
 Info necessary to use FSPs/BPAs to control system p CECs/Frames.
 


ppchcp(5)|ppchcp.5
 
 Info necessary to use HMCs and IVMs as hardware control points for LPARs.
 


prescripts(5)|prescripts.5
 
 The scripts that will be run at the beginning and the end of the nodeset(Linux), nimnodeset(AIX) or mkdsklsnode(AIX) command.
 


prodkey(5)|prodkey.5
 
 Specify product keys for products that require them
 


rack(5)|rack.5
 
 Rack information.
 


routes(5)|routes.5
 
 Describes the additional routes needed to be setup in the os routing table. These routes usually are used to connect the management node to the compute node using the service node as gateway.
 


servicenode(5)|servicenode.5
 
 List of all Service Nodes and services that will be set up on the Service Node.
 


site(5)|site.5
 
 Global settings for the whole cluster.  This table is different from the 
 other tables in that each attribute is just named in the key column, rather 
 than having a separate column for each attribute. The following is a list of 
 attributes currently used by xCAT organized into categories.
 


statelite(5)|statelite.5
 
 The location on an NFS server where a nodes persistent files are stored.  Any file marked persistent in the litefile table will be stored in the location specified in this table for that node.
 


storage(5)|storage.5



switch(5)|switch.5
 
 Contains what switch port numbers each node is connected to.
 


switches(5)|switches.5
 
 Parameters to use when interrogating switches
 


taskstate(5)|taskstate.5
 
 The task state for the node.
 


token(5)|token.5
 
 The token of users for authentication.
 


virtsd(5)|virtsd.5
 
 The parameters which used to create the Storage Domain
 


vm(5)|vm.5
 
 Virtualization parameters
 


vmmaster(5)|vmmaster.5
 
 Inventory of virtualization images for use with clonevm.  Manual intervention in this table is not intended.
 


vpd(5)|vpd.5
 
 The Machine type, Model, and Serial numbers of each node.
 


websrv(5)|websrv.5
 
 Web service parameters
 


winimage(5)|winimage.5
 
 Information about a Windows operating system image that can be used to deploy cluster nodes.
 


zone(5)|zone.5
 
 Defines a cluster zone for nodes that share root ssh key access to each other.
 


zvm(5)|zvm.5
 
 List of z/VM virtual servers.
 



********
SEE ALSO
********


\ **nodels(1)**\ , \ **chtab(8)**\ , \ **tabdump(8)**\ , \ **tabedit(8)**\ , \ **lsdef(1)**\ , \ **mkdef(1)**\ , \ **chdef(1)**\ , \ **rmdef(1)**\ 

