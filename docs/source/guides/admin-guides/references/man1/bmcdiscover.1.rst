
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

\ **bmcdiscover**\  [\ **-s**\  \ *scan_method*\ ] [\ **-u**\  \ *bmc_user*\ ] [\ **-p**\  \ *bmc_passwd*\ ] [\ **-z**\ ] [\ **-w**\ ] \ **-**\ **-range**\  \ *ip_ranges*\ 

\ **bmcdiscover**\  \ **-u**\  \ *bmc_user*\  \ **-p**\  \ *bmc_passwd*\  \ **-i**\  \ *bmc_ip*\  \ **-**\ **-check**\ 

\ **bmcdiscover**\  [\ **-u**\  \ *bmc_user*\ ] [\ **-p**\  \ *bmc_passwd*\ ] \ **-i**\  \ *bmc_ip*\  \ **-**\ **-ipsource**\ 


***********
DESCRIPTION
***********


The \ **bmcdiscover**\  command will discover Baseboard Management Controllers (BMCs) using a scan mathod.

The command uses \ **nmap**\  to scan active nodes over a specified IP range.  The IP range format should be a format that is acceptable by \ **nmap**\ .

The \ **bmcdiscover**\  command can also obtain some information about the BMC. (Check username/password, IP address source, DHCP/static configuration)

Note: The scan method currently support is \ **nmap**\ .


*******
OPTIONS
*******



\ **-**\ **-range**\ 
 
 Specify one or more IP ranges acceptable to nmap.  IP rance can be hostnames, IP addresses, networks, etc.  A single IP address (10.1.2.3) or an IP range (10.1.2.0/24) can be specified.  If the range is very large, the \ **bmcdiscover**\  command may take a long time to return.
 


\ **-s**\ 
 
 Scan method  (The only supported scan method at this time is \ **nmap**\ )
 


\ **-z**\ 
 
 List the data returned in xCAT stanza format
 


\ **-w**\ 
 
 Write to the xCAT database.
 


\ **-i|-**\ **-bmcip**\ 
 
 BMC IP address.
 


\ **-u|-**\ **-bmcuser**\ 
 
 BMC user name.
 


\ **-p|-**\ **-bmcpasswd**\ 
 
 BMC user password.
 


\ **-**\ **-check**\ 
 
 Check BMC administrator User/Password.
 


\ **-**\ **-ipsource**\ 
 
 Display the BMC IP configuration.
 


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


1. To get all responding BMCs from IP range "10.4.23.100-254" and 50.3.15.1-2":


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.23.100-254 50.3.15.1-2"


Note: Input for IP range can be in the form: scanme.nmap.org, microsoft.com/24, 192.168.0.1; 10.0.0-255.1-254.

2. To get all BMSs in IP range "10.4.22-23.100-254", displayed in xCAT stanza format:


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.22-23.100-254" -z


3. Discover the BMCs and write the discovered-node definitions into the xCAT database and write out the stanza foramt to the console:


.. code-block:: perl

     bmcdiscover -s nmap --range "10.4.22-23.100-254" -w -z


4. To check if the username or password is correct against the BMC:


.. code-block:: perl

     bmcdiscover -i 10.4.23.254 -u USERID -p PASSW0RD --check


5. Get BMC IP Address source, DHCP Address or static Address


.. code-block:: perl

     bmcdiscover -i 10.4.23.254 -u USERID -p PASSW0RD --ipsource



********
SEE ALSO
********


lsslp(1)|lsslp.1

