
#############
bmcdiscover.1
#############

.. highlight:: perl


****
NAME
****


\ **bmcdiscover**\  - Discover Baseboard Management Controllers (BMCs) using a scan method


********
SYNOPSIS
********


\ **bmcdiscover**\  [\ **-? | -h | -**\ **-help**\ ]

\ **bmcdiscover**\  [\ **-v | -**\ **-version**\ ]

\ **bmcdiscover**\   \ **-**\ **-range**\  \ *ip_ranges*\  [\ **-**\ **-sn**\  \ *SN_nodename*\ ] [\ **-s**\  \ *scan_method*\ ] [\ **-u**\  \ *bmc_user*\ ] [\ **-p**\  \ *bmc_passwd*\ ] [\ **-z**\ ] [\ **-w**\ ]


***********
DESCRIPTION
***********


The \ **bmcdiscover**\  command will discover Baseboard Management Controllers (BMCs) using a scan method.

The command uses \ **nmap**\  to scan active nodes over a specified IP range.  The IP range format should be a format that is acceptable by \ **nmap**\ .

\ **Note:**\  The scan method currently supported is \ **nmap**\ .

\ **Note:**\  Starting on January 1, 2020, some newly shipped systems will require the default BMC password to be changed before they can be managed by xCAT. \ **bmcdiscover**\  will not be able to discover such systems. Run \ */opt/xcat/share/xcat/scripts/BMC_change_password.sh*\  script to change the default password for BMCs in specified range, then rerun \ **bmcdiscover**\  with \ **-p "new bmc password"**\  flag to discover systems with the changed password.


*******
OPTIONS
*******



\ **-**\ **-range**\ 
 
 Specify one or more IP ranges acceptable to \ **nmap**\ .  IP range can be hostnames, IP addresses, networks, etc.  A single IP address (10.1.2.3), several IPs with commas (10.1.2.3,10.1.2.10), IP range with "-" (10.1.2.0-100) or an IP range (10.1.2.0/24) can be specified.  If the range is very large, the \ **bmcdiscover**\  command may take a long time to return.
 


\ **-**\ **-sn**\ 
 
 Specify one or more service nodes on which \ **bmcdiscover**\  will run. In hierarchical cluster, the MN may not be able to access the BMC of CN directly, but SN can. In that case, \ **bmcdiscover**\  will be dispatched to the specified SNs. Then, the nodename of the service node that \ **bmcdiscover**\  is running on will be set to the 'servicenode' attribute of the discovered BMC node.
 


\ **-s**\ 
 
 Scan method  (The only supported scan method at this time is \ **nmap**\ )
 


\ **-z**\ 
 
 List the data returned in xCAT stanza format
 


\ **-w**\ 
 
 Write to the xCAT database.
 


\ **-u|-**\ **-bmcuser**\ 
 
 BMC user name.
 


\ **-p|-**\ **-bmcpasswd**\ 
 
 BMC user password.
 


\ **-h|-**\ **-help**\ 
 
 Display usage message
 


\ **-v|-**\ **-version**\ 
 
 Display version information
 



************
RETURN VALUE
************


0  The command completed successfully.

1  An error has occurred.


********
EXAMPLES
********


1. To get all responding BMCs from IP range "10.4.23.100-254" and "50.3.15.1-2":


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.23.100-254 50.3.15.1-2"


Note: Input for IP range can be in the form: scanme.nmap.org, microsoft.com/24, 192.168.0.1; 10.0.0-255.1-254.

2. To get all BMCs in IP range "10.4.22-23.100-254", displayed in xCAT stanza format:


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.22-23.100-254" -z


3. To discover BMCs through sn01:


.. code-block:: perl

     bmcdiscover --sn sn01 -s nmap --range "10.4.22-23.100-254" -z


Output is similar to:


.. code-block:: perl

     node-70e28414291b:
         objtype=node
         groups=all
         bmc=10.4.22.101
         cons=openbmc
         mgt=openbmc
         servicenode=sn01
         conserver=sn01


4. Discover the BMCs and write the discovered node definitions into the xCAT database and write out the stanza format to the console:


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.22-23.100-254" -w -z



********
SEE ALSO
********


lsslp(1)|lsslp.1

