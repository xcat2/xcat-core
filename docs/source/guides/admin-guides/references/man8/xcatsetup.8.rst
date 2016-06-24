
###########
xcatsetup.8
###########

.. highlight:: perl


****
NAME
****


\ **xcatsetup**\  - Prime the xCAT database using naming conventions specified in a config file.


********
SYNOPSIS
********


\ **xcatsetup**\  [\ **-s|-**\ **-stanzas**\  \ *stanza-list*\ ] [\ **-**\ **-yesreallydeletenodes**\ ] \ *cluster-config-file*\ 

\ **xcatsetup**\  [\ **-?**\  | \ **-h**\  | \ **-**\ **-help**\  | \ **-v**\  | \ **-**\ **-version**\ ]


***********
DESCRIPTION
***********


The \ **xcatsetup**\  command reads the specified config file that contains general information about the cluster being set up,
and naming conventions and IP addresses that you want to use.  It then defines the basic objects in the xCAT database
representing this cluster configuration.  The \ **xcatsetup**\  command prepares the database for the step of discovering
the hardware that is connected to the service and cluster networks.  The typical steps of setting up a system p cluster are:


1.
 
 Install the xCAT software on the management node
 


2.
 
 Create the cluster config file and run xcatsetup
 


3.
 
 Put hardware control passwords in the ppchcp or ppcdirect database table
 


4.
 
 Run makenetworks and makedhcp
 


5.
 
 Run the discovery commands (lsslp, mkhwconn, rspconfig) as described in the System P Hardware Management cookbook.
 


6.
 
 Configure and start services using makehosts, makedns, mkconserver.cf, etc.
 


7.
 
 Create the images that should be installed or booted on the nodes
 


8.
 
 Run nodeset and rpower/rnetboot to boot up the nodes.
 


The \ **xcatsetup**\  command is intended as a quick way to fill out the database for a cluster that has very regular
naming patterns.  The only thing it does is fill in database attributes.  If your cluster does not follow consistent
naming patterns, or has some other special configuration, you should define attribute values manually using mkdef(1)|mkdef.1, instead of using
\ **xcatsetup**\ .  The cluster config file is meant to be an easy way to prime the database; it is not meant to be a
long living file that you update as the cluster changes.  If you do want to run xcatsetup again at a later time,
because, for example, you added a lot of nodes, you should put the total list of nodes in the config file, not just
the new ones.  This is because xcatsetup uses some regular expressions for groups (e.g. frame, cec, compute) that would
be calculated incorrectly if the config file told xcatsetup about only the new nodes.

Speaking of regular expressions, xcatsetup creates some pretty complicated regular expressions in the database.
These are useful because they keep most of the tables small, even for large clusters.  But if you want to
tweak them, they may be hard to understand.  If after running xcatsetup, you want to convert your database to
use individual rows for every node, you can do the following:


.. code-block:: perl

   lsdef -z all >tmp.stanza
   cat tmp.stanza | chdef -z


Many of the sections and attributes in the configuration file can be omitted, if you have a simple cluster, or if you want
to create just 1 or 2 of the object types at this time.  See the section \ **A Simpler Configuration File**\  for an example of this.

If you want to delete all of the nodes that xcatsetup created, and start over, use the \ **-**\ **-yesreallydeletenodes**\  option.

Restrictions
============



1. The \ **xcatsetup**\  command has only been implemented and tested for system p servers so far.




Configuration File
==================


The \ **config file**\  is organized in stanza format and supports the keywords in the sample file below.  Comment lines
begin with "#".  Stanzas can be ommitted if you do not want to define that type of object.
The only hostname formats supported are those shown in this sample file, although you can change the base
text and the numbers.  For example, hmc1-hmc3 could be changed to hwmgmt01-hwmgmt12.
The hostnames specified must sort correctly.  I.e. use node01-node80, instead of node1-node80.
This sample configuration file is for a 2 building block cluster.


.. code-block:: perl

   xcat-site:
    domain = cluster.com
    # currently only direct fsp control is supported
    use-direct-fsp-control = 1
    # ISR network topology.  For example, one of the following: 128D, 64D, 32D, 16D, 8D, 4D, 2D, 1D
    topology = 32D
    # The nameservers in site table will be set with the value of master automatically.
 
   xcat-service-lan:
     # IP range used for DHCP. If you set the entry, the networks table will be filled
     # automatically with this range and the dhcp interface will be set in the site table.
     dhcp-dynamic-range = 50.0.0.0-50.0.0.200
 
   xcat-hmcs:
    hostname-range = hmc1-hmc2
    starting-ip = 10.200.1.1
 
   xcat-frames:
    # these are the connections to the frames
    hostname-range = frame[1-6]
    num-frames-per-hmc = 3
    # this lists which serial numbers go with which frame numbers
    vpd-file = vpd2bb.stanza
    # There are two rules of defining FSP/BPAs. The first defining the node's host name by increasing the last bit
    # of IP address, while the second defining the node's name by varying the second bit and the third bit of IP.
    # This assumes you have 2 service LANs:  a primary service LAN 10.230.0.0/255.255.0.0 that all of the port 0's
    # are connected to, and a backup service LAN 10.231.0.0/255.255.0.0 that all of the port 1's are connected to.
    # bpa-a-0-starting-ip = 10.230.1.1
    # bpa-b-0-starting-ip = 10.230.2.1
    # bpa-a-1-starting-ip = 10.231.1.1
    # bpa-b-1-starting-ip = 10.231.2.1
    # This assumes you have 2 service LANs:  a primary service LAN 40.x.y.z/255.0.0.0 that all of the port 0's
    # are connected to, and a backup service LAN 41.x.y.z/255.0.0.0 that all of the port 1's are connected to.
    # "x" is the frame number and "z" is the bpa/fsp id (1 for the first BPA/FSP in the Frame/CEC, 2 for the 
    # second BPA/FSP in the Frame/CEC). For BPAs "y" is always be 0 and for FSPs "y" is the cec id.
    vlan-1 = 40
    vlan-2 = 41
 
 
   xcat-cecs:
    # These are the connections to the CECs.  Either form of hostname is supported.
    #hostname-range = cec01-cec64
    hostname-range = f[1-6]c[01-12]
    # If you use the frame/cec hostname scheme above, but do not have a consistent
    # number of cecs in each frame, xcat can delete the cecs that do not get
    # supernode numbers assigned to them.
    delete-unused-cecs = 1
    # lists the HFI supernode numbers for each group of cecs in each frame
    supernode-list = supernodelist2bb.txt
    # If you do not want to specify the supernode-list at this time and you have a consistent
    # number of cecs in each frame, you can instead just use this setting:
    num-cecs-per-frame = 12
    #fsp-a-0-starting-ip = 10.230.3.1
    #fsp-b-0-starting-ip = 10.230.4.1
    #fsp-a-1-starting-ip = 10.231.3.1
    #fsp-b-1-starting-ip = 10.231.4.1
 
 
   xcat-building-blocks:
    num-frames-per-bb = 3
    num-cecs-per-bb = 32
 
   xcat-lpars:
    num-lpars-per-cec = 8
    # If you set these, then do not set the corresponding attributes in the other node stanzas below.
    # Except you still need to set xcat-service-nodes:starting-ip (which is the ethernet adapter)
    #hostname-range = f[1-6]c[01-12]p[1-8]
    hostname-range = f[1-6]c[01-12]p[01,05,09,13,17,21,25,29]
    starting-ip = 10.1.1.1
    aliases = -hf0
    # ml0 is for aix.  For linux, use bond0 instead.
    otherinterfaces = -hf1:11.1.1.1,-hf2:12.1.1.1,-hf3:13.1.1.1,-ml0:14.1.1.1
 
   xcat-service-nodes:
    num-service-nodes-per-bb = 2
    # which cecs within the bldg block that the SNs are located in
    cec-positions-in-bb = 1,32
    # this is for the ethernet NIC on each SN
    #hostname-range = sn1-sn4
    starting-ip = 10.10.1.1
    # this value is the same format as the hosts.otherinterfaces attribute except
    # the IP addresses are starting IP addresses
    #otherinterfaces = -hf0:10.10.1.1,-hf1:10.11.1.1,-hf2:10.12.1.1,-hf3:10.13.1.1,-ml0:10.14.1.1
 
   xcat-storage-nodes:
    num-storage-nodes-per-bb = 3
    # which cecs within the bldg block that the storage nodes are located in
    cec-positions-in-bb = 12,20,31
    #hostname-range = stor1-stor6
    #starting-ip = 10.20.1.1
    #aliases = -hf0
    #otherinterfaces = -hf1:10.21.1.1,-hf2:10.22.1.1,-hf3:10.23.1.1,-ml0:10.24.1.1
 
   xcat-compute-nodes:
    #hostname-range = n001-n502
    #starting-ip = 10.30.1.1
    #aliases = -hf0
    # ml0 is for aix.  For linux, use bond0 instead.
    #otherinterfaces = -hf1:10.31.1.1,-hf2:10.32.1.1,-hf3:10.33.1.1,-ml0:10.34.1.1



VPD File for Frames
===================


The \ **vpd-file**\  specifies the following vpd table attributes for the frames:  node,
serial, mtm, side.  Use the same stanza format that accepted by the chdef(1)|chdef.1 command, as documented
in xcatstanzafile(5)|xcatstanzafile.5.  The purpose of this file is to enable xCAT to match up frames found
through lsslp(1)|lsslp.1 discovery with the database objects created by \ **xcatsetup**\ .  All of the frames
in the cluster must be specified.

Here is a sample file:


.. code-block:: perl

   frame1:
     objtype=node
     serial=99200G1
     mtm=9A00-100
   frame2:
     objtype=node
     serial=99200D1
     mtm=9A00-100
   frame3:
     objtype=node
     serial=99200G1
     mtm=9A00-100
   frame4:
     objtype=node
     serial=99200D1
     mtm=9A00-100
   frame5:
     objtype=node
     serial=99200G1
     mtm=9A00-100
   frame6:
     objtype=node
     serial=99200D1
     mtm=9A00-100



Supernode Numbers for CECs
==========================


The \ **supernode-list**\  file lists what supernode numbers should be given to each CEC in each frame.
Here is a sample file:


.. code-block:: perl

   frame1: 0, 1, 16
   frame2: 17, 32
   frame3: 33, 48, 49
   frame4: 64 , 65, 80
   frame5: 81, 96
   frame6: 97(1), 112(1), 113(1), 37(1), 55, 71


The name before the colon is the node name of the frame.  The numbers after the colon are the supernode numbers
to assign to the groups of CECs in that frame from bottom to top.  Each supernode contains 4 CECs, unless it is immediately
followed by "(#)", in which case the number in parenthesis indicates how many CECs are in this supernode.


A Simpler Configuration File
============================


This is an example of a simple cluster config file that just defines the frames and CECs for 2 frames, without specifying
VPD data or supernode numbers at this time.


.. code-block:: perl

   xcat-site:
    use-direct-fsp-control = 1
 
   xcat-frames:
    hostname-range = frame[1-2]
 
   xcat-cecs:
    #hostname-range = cec[01-24]
    hostname-range = f[1-2]c[01-12]
    num-cecs-per-frame = 12
 
 
   xcat-lpars:
     hostname-range = f[1-2]c[01-12]p[01,05,09,13,17,21,25,29]



Database Attributes Written
===========================


The following lists which database attributes are filled in as a result of each stanza.  Note that depending on the values
in the stanza, some attributes might not be filled in.


\ **xcat-site**\ 
 
 site table:  domain, nameservers, topology
 


\ **xcat-hmcs**\ 
 
 site table:  ea_primary_hmc, ea_backup_hmc
 
 nodelist table:  node, groups (all HMCs (hmc) ), hidden
 
 hosts table:  node, ip
 
 ppc table:  node, comments
 
 nodetype table:  node, nodetype
 


\ **xcat-frames**\ 
 
 nodelist table:  node, groups (all frames (frame) ), hidden
 
 ppc table: node, id, hcp, nodetype, sfp
 
 nodetype table: node, nodetype
 
 nodehm table: node, mgt
 
 vpd table: node, serial, mtm, side
 


\ **xcat-bpas**\ 
 
 nodelist table: node, groups (bpa,all) , hidden
 
 ppc table: node, id, hcp, nodetype, parent
 
 nodetype table:  node, nodetype
 
 nodehm table:  node, mgt
 
 vpd table:  node, serial, mtm, side
 


\ **xcat-cecs**\ 
 
 nodelist table:  node, groups (all CECs (cec), all CECs in a frame (<frame>cec) ), hidden
 
 ppc table:  node, supernode, hcp, id, parent
 
 nodetype table:  node, nodetype
 
 nodehm table:  node, mgt
 
 nodegroup table:  groupname, grouptype, members, wherevals (all nodes in a CEC (<cec>nodes) )
 
 nodepos:  rack, u
 


\ **xcat-fsps**\ 
 
 nodelist table: node, groups (fsp,all), hidden
 
 ppc table: node, id, hcp, nodetype, parent
 
 nodetype table: node, nodetype
 
 nodehm table: node, mgt
 
 vpd table: node, serial, mtm, side
 


\ **xcat-building-blocks**\ 
 
 site table: sharedtftp, sshbetweennodes(service)
 
 ppc table:  node, parent (for frame)
 


\ **xcat-service-nodes**\ 
 
 nodelist table:  node, groups (all service nodes (service), all service nodes in a BB (bb<num>service) )
 
 hosts table:  node, ip, hostnames, otherinterfaces
 
 ppc table:  node, id, hcp, parent
 
 nodetype table:  node, nodetype, arch
 
 nodehm table:  node, mgt, cons
 
 noderes table:  netboot
 
 servicenode table:  node, nameserver, dhcpserver, tftpserver, nfsserver, conserver, monserver, ftpserver, nimserver, ipforward
 
 nodegroup table:  groupname, grouptype, members, wherevals (all nodes under a service node (<servicenode>nodes) )
 
 nodepos:  rack, u
 


\ **xcat-storage-nodes**\ 
 
 nodelist table:  node, groups (all storage nodes (storage), all storage nodes in a BB (bb<num>storage) )
 
 hosts table:  node, ip, hostnames, otherinterfaces
 
 ppc table:  node, id, hcp, parent
 
 nodetype table:  node, nodetype, arch
 
 nodehm table:  node, mgt, cons
 
 noderes table:  netboot, xcatmaster, servicenode
 
 nodepos:  rack, u
 


\ **xcat-compute-nodes**\ 
 
 nodelist table:  node, groups (all compute nodes (compute) )
 
 hosts table:  node, ip, hostnames, otherinterfaces
 
 ppc table:  node, id, hcp, parent
 
 nodetype table:  node, nodetype, arch
 
 nodehm table:  node, mgt, cons
 
 noderes table:  netboot, xcatmaster, servicenode
 
 nodepos:  rack, u
 


\ **ll-config**\ 
 
 postscripts: postscripts
 




*******
OPTIONS
*******



\ **-s|-**\ **-stanzas**\  \ *stanza-list*\ 
 
 A comma-separated list of stanza names that \ **xcatsetup**\  should process in the configuration file.  If not specified, it will process
 all the stanzas that start with 'xcat' and some other stanzas that give xCAT hints about how to set up the HPC products.
 
 This option should only be specified if you have already run \ **xcatsetup**\  earlier with the stanzas that occur before this in the
 configuration file.  Otherwise, objects will be created that refer back to other objects that do not exist in the database.
 


\ **-v|-**\ **-version**\ 
 
 Command Version.
 


\ **-?|-h|-**\ **-help**\ 
 
 Display usage message.
 


\ **-**\ **-yesreallydeletenodes**\ 
 
 Delete the nodes represented in the cluster config file, instead of creating them.  This is useful if your first attempt with the cluster
 config file wasn't quite right and you want to start over.  But use this option with extreme caution, because it will potentially delete
 a lot of nodes.  If the only thing you have done so far in your database is add nodes by running \ **xcatsetup**\ , then it is safe to use this
 option to start over.  If you have made other changes to your database, you should first back it up using dumpxCATdb(1)|dumpxCATdb.1 before
 using this option.
 



************
RETURN VALUE
************



0.   The command completed successfully.



1.   An error has occurred.




********
EXAMPLES
********



1. Use the sample config.txt file at the beginning of this man page to create all the objects/nodes for a
2 building block cluster.
 
 
 .. code-block:: perl
 
   xcatsetup config.txt
 
 
 The output:
 
 
 .. code-block:: perl
 
   Defining site attributes...
   Defining HMCs...
   Defining frames...
   Defining CECs...
   Defining building blocks...
   Defining LPAR nodes...
 
 


2. Use the simpler config file shown earlier in this man page to create just the frame and cec objects:
 
 
 .. code-block:: perl
 
   xcatsetup config-simple.txt
 
 
 The output:
 
 
 .. code-block:: perl
 
   Defining frames...
   Defining CECs...
 
 



*****
FILES
*****


/opt/xcat/sbin/xcatsetup


********
SEE ALSO
********


mkdef(1)|mkdef.1, chdef(1)|chdef.1, lsdef(1)|lsdef.1, xcatstanzafile(5)|xcatstanzafile.5, noderange(3)|noderange.3, nodeadd(8)|nodeadd.8

