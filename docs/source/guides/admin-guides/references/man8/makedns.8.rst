
#########
makedns.8
#########

.. highlight:: perl


****
NAME
****


\ **makedns**\  - sets up domain name services (DNS).


********
SYNOPSIS
********


\ **makedns**\  [\ **-h | -**\ **-help**\ ]

\ **makedns**\  [\ **-V | -**\ **-verbose**\ ] [\ **-e | -**\ **-external**\ ] [\ **-n | -**\ **-new**\ ] [\ *noderange*\ ]

\ **makedns**\  [\ **-V | -**\ **-verbose**\ ] [\ **-e | -**\ **-external**\ ] [\ **-d | -**\ **-delete**\  \ *noderange*\ ]


***********
DESCRIPTION
***********


\ **makedns**\  configures a DNS server on the system you run it on, which is typically the xCAT management node.

The list of nodes to include comes from either the \ **noderange**\  provided on the command line or the entries in the local /etc/hosts files.

There are several bits of information that must be included in the xCAT database before running this command.

You must set the \ **forwarders**\  attributes in the xCAT \ **site**\  definition.

The \ **forwarders**\  value should be set to the IP address of one or more nameservers at your site that can resolve names outside of your cluster.  With this set up, all nodes ask the local nameserver to resolve names, and if it is a name that the MN DNS does not know about, it will try the forwarder names.

An xCAT \ **network**\  definition must be defined for each network used in the cluster.  The \ **net**\  and \ **mask**\  attributes will be used by the \ **makedns**\  command.

A network \ **domain**\  and \ **nameservers**\  values must be provided either in the \ **network**\  definiton corresponding to the node or in the \ **site**\  definition.

Only entries in /etc/hosts or the hosts specified by \ **noderange**\  that have a corresponding xCAT network definition will be added to DNS.

By default, \ **makedns**\  sets up the \ **named**\  service and updates the DNS records on the local system (management node). If the -e flag is specified, it will also update the DNS records on any external DNS server that is listed in the /etc/resolv.conf on the management node. (Assuming the external DNS server can recognize the xCAT key as authentication.)

For more information on Cluster Name Resolution:
Cluster_Name_Resolution


*******
OPTIONS
*******



\ **-V | -**\ **-verbose**\ 
 
 Verbose mode.
 


\ **-n | -**\ **-new**\ 
 
 Use this flag to create new named configuration and db files.
 


\ **-d | -**\ **-delete**\ 
 
 Remove the DNS records.
 


\ **-e | -**\ **-external**\ 
 
 Update DNS records to the external DNS server listed in /etc/resolv.conf.
 
 Enabling the site attribute \ *externaldns*\  means use 'external' DNS by default. If setting \ *externaldns*\  to 1, you need NOT use \ **-e**\  flag in every makedns call.
 


\ **noderange**\ 
 
 A set of comma delimited node names and/or group names. See the "noderange" man page for details on additional supported formats.
 



********
Examples
********



1. To set up DNS for all the hosts in /etc/hosts file.
 
 
 .. code-block:: perl
 
   makedns
 
 


2. To set up DNS for \ *node1*\ .
 
 
 .. code-block:: perl
 
   makedns node1
 
 


3. To create a new named configuration and db files for all hosts in /etc/hosts.
 
 
 .. code-block:: perl
 
   makedns -n
 
 


4. To delete the DNS records for \ *node1*\ .
 
 
 .. code-block:: perl
 
   makedns -d node1
 
 



********
SEE ALSO
********


makehosts(8)|makehosts.8

